package com.zitlas.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId

/**
 * ZITLAS native step source.
 *
 * TWO sources, never summed together (that would double-count the same walk):
 *
 *  1. HEALTH CONNECT — the source of truth whenever it's installed and the
 *     READ_STEPS permission is granted. Read exclusively through the
 *     platform's own AGGREGATE api (`StepsRecord.COUNT_TOTAL`), never by
 *     summing raw records: Health Connect can hold overlapping step records
 *     written by several providers (Fit, an OEM health app, a watch), and its
 *     aggregate is the only thing that deduplicates them correctly. Summing
 *     `readRecords()` ourselves is exactly how you get impossible counts.
 *
 *  2. HARDWARE TYPE_STEP_COUNTER — the fallback. The step-counter chip
 *     accumulates steps continuously in hardware while this process is dead
 *     and the screen is locked, at effectively no battery cost, which is what
 *     lets ZITLAS capture a walk without running a foreground service. It
 *     reports steps SINCE BOOT, so Dart turns it into a daily figure using a
 *     persisted baseline (see step_sensor_source.dart) — the boot timestamp
 *     returned here is what makes reboot detection possible.
 *
 * This plugin deliberately exposes only "read step count" — no other health
 * data type is touched or requested.
 */
class StepTrackerPlugin(
    private val activity: ComponentActivity,
    messenger: io.flutter.plugin.common.BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.zitlas.app/steps"
        private val PERMISSIONS = setOf(HealthPermission.getReadPermission(StepsRecord::class))
        private const val HC_PROVIDER_PACKAGE = "com.google.android.apps.healthdata"
    }

    private val channel = MethodChannel(messenger, CHANNEL).also { it.setMethodCallHandler(this) }
    private val scope = CoroutineScope(Dispatchers.Main)

    /** Set while an HC permission sheet is open, completed by its callback. */
    private var pendingPermissionResult: MethodChannel.Result? = null

    private val permissionLauncher: ActivityResultLauncher<Set<String>> =
        activity.registerForActivityResult(
            PermissionController.createRequestPermissionResultContract()
        ) { granted ->
            val result = pendingPermissionResult
            pendingPermissionResult = null
            result?.success(granted.containsAll(PERMISSIONS))
        }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getStatus" -> result.success(buildStatus())
            "requestHealthConnectPermission" -> requestHealthConnectPermission(result)
            "getStepsBetween" -> getStepsBetween(call, result)
            "readStepSensor" -> readStepSensor(result)
            "openHealthConnectSettings" -> {
                result.success(openHealthConnectSettings())
            }
            // Arms the native midnight capture. Called from Dart on every
            // launch so the alarm is repaired if Android ever dropped it (a
            // force-stop clears an app's alarms, and only reopening restores
            // them).
            "scheduleDayBoundary" -> {
                StepDayBoundary.scheduleNext(activity.applicationContext)
                result.success(true)
            }
            // Hands Dart whatever the midnight receiver captured, then clears
            // it. Consume-once: the reading is folded into the daily record on
            // the Dart side, and replaying it later would re-apply a boundary
            // that has already been accounted for.
            "consumeDayBoundary" -> {
                val prefs = StepDayBoundary.prefs(activity.applicationContext)
                val json = prefs.getString(StepDayBoundary.KEY_BOUNDARY, null)
                if (json != null) {
                    prefs.edit().remove(StepDayBoundary.KEY_BOUNDARY).commit()
                }
                result.success(json)
            }
            else -> result.notImplemented()
        }
    }

    // ── Status ────────────────────────────────────────────────────────────

    /**
     * Reports what's actually usable on THIS device, so Dart can pick a source
     * and the UI can show a truthful state instead of a silent 0. Every field
     * is a real device query — nothing is assumed.
     */
    private fun buildStatus(): Map<String, Any?> {
        val sdkStatus = try {
            HealthConnectClient.getSdkStatus(activity, HC_PROVIDER_PACKAGE)
        } catch (e: Throwable) {
            HealthConnectClient.SDK_UNAVAILABLE
        }
        val hcState = when (sdkStatus) {
            HealthConnectClient.SDK_AVAILABLE -> "available"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "updateRequired"
            else -> "unavailable"
        }
        return mapOf(
            "healthConnect" to hcState,
            "sensorAvailable" to hasStepSensor(),
            "activityRecognitionGranted" to hasActivityRecognitionPermission(),
        )
    }

    private fun hasStepSensor(): Boolean {
        val sm = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager ?: return false
        return sm.getDefaultSensor(Sensor.TYPE_STEP_COUNTER) != null
    }

    private fun hasActivityRecognitionPermission(): Boolean {
        // Only enforced from API 29; below that the manifest grant is enough.
        if (android.os.Build.VERSION.SDK_INT < 29) return true
        return activity.checkSelfPermission(android.Manifest.permission.ACTIVITY_RECOGNITION) ==
            PackageManager.PERMISSION_GRANTED
    }

    // ── Health Connect permission ─────────────────────────────────────────

    private fun requestHealthConnectPermission(result: MethodChannel.Result) {
        val client = healthConnectClientOrNull()
        if (client == null) {
            // Not an error state the user can act on from here — Dart decides
            // whether to offer "install Health Connect" or fall back to the
            // sensor. Never crash, never pretend it succeeded.
            result.success(false)
            return
        }
        scope.launch {
            try {
                val granted = client.permissionController.getGrantedPermissions()
                if (granted.containsAll(PERMISSIONS)) {
                    result.success(true)
                    return@launch
                }
                if (pendingPermissionResult != null) {
                    // A sheet is already open; don't stack a second request.
                    result.success(false)
                    return@launch
                }
                pendingPermissionResult = result
                permissionLauncher.launch(PERMISSIONS)
            } catch (e: Throwable) {
                pendingPermissionResult = null
                result.success(false)
            }
        }
    }

    private fun openHealthConnectSettings(): Boolean {
        return try {
            val intent = Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (e: Throwable) {
            // Fall back to the provider's Play Store page (Android 13 and
            // below, where Health Connect is an installable app).
            try {
                val store = Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse("market://details?id=$HC_PROVIDER_PACKAGE")
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(store)
                true
            } catch (e2: Throwable) {
                false
            }
        }
    }

    private fun healthConnectClientOrNull(): HealthConnectClient? {
        return try {
            if (HealthConnectClient.getSdkStatus(activity, HC_PROVIDER_PACKAGE) !=
                HealthConnectClient.SDK_AVAILABLE
            ) {
                null
            } else {
                HealthConnectClient.getOrCreate(activity)
            }
        } catch (e: Throwable) {
            null
        }
    }

    // ── Health Connect aggregate read ─────────────────────────────────────

    /**
     * Total steps in [startMillis, endMillis) via Health Connect's own
     * aggregate. Dart passes an explicit LOCAL-midnight..now window; the
     * boundary is never computed here so there's exactly one definition of
     * "today" in the codebase.
     *
     * Returns a map with `granted` and `steps`. `steps == null` means "no
     * usable Health Connect answer" (not installed, not granted, or it threw)
     * — distinct from `steps == 0`, which is a real "you haven't walked yet".
     * Collapsing those two is how a broken integration ends up looking like a
     * lazy morning.
     */
    private fun getStepsBetween(call: MethodCall, result: MethodChannel.Result) {
        val startMillis = (call.argument<Number>("startMillis"))?.toLong()
        val endMillis = (call.argument<Number>("endMillis"))?.toLong()
        if (startMillis == null || endMillis == null || endMillis <= startMillis) {
            result.success(mapOf("granted" to false, "steps" to null))
            return
        }
        val client = healthConnectClientOrNull()
        if (client == null) {
            result.success(mapOf("granted" to false, "steps" to null))
            return
        }
        scope.launch {
            try {
                val granted = client.permissionController.getGrantedPermissions()
                if (!granted.containsAll(PERMISSIONS)) {
                    result.success(mapOf("granted" to false, "steps" to null))
                    return@launch
                }
                val response: AggregationResult = withContext(Dispatchers.IO) {
                    client.aggregate(
                        AggregateRequest(
                            metrics = setOf(StepsRecord.COUNT_TOTAL),
                            timeRangeFilter = TimeRangeFilter.between(
                                Instant.ofEpochMilli(startMillis),
                                Instant.ofEpochMilli(endMillis),
                            ),
                        )
                    )
                }
                // Null here legitimately means "no step records in the window"
                // (aggregate returns null, not 0, for an empty range) — and
                // with the permission confirmed granted above, that IS a real
                // zero, so report it as such rather than as "unavailable".
                val steps = response[StepsRecord.COUNT_TOTAL] ?: 0L
                result.success(mapOf("granted" to true, "steps" to steps.toInt()))
            } catch (e: Throwable) {
                result.success(mapOf("granted" to false, "steps" to null))
            }
        }
    }

    // ── Hardware step counter ─────────────────────────────────────────────

    /**
     * One-shot read of TYPE_STEP_COUNTER's since-boot total.
     *
     * `bootTimeMillis` (wall-clock time of the last boot) travels with the
     * reading so Dart can tell a reboot — which silently resets this counter
     * to 0 — apart from a genuine step decrease, and discard a stale baseline
     * instead of reporting a huge negative delta.
     */
    private fun readStepSensor(result: MethodChannel.Result) {
        if (!hasActivityRecognitionPermission()) {
            result.success(null)
            return
        }
        val sm = activity.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sm == null || sensor == null) {
            result.success(null)
            return
        }

        var settled = false
        val handler = Handler(Looper.getMainLooper())
        var listener: SensorEventListener? = null

        fun finish(value: Int?) {
            if (settled) return
            settled = true
            listener?.let { sm.unregisterListener(it) }
            result.success(
                if (value == null) null
                else mapOf(
                    "cumulative" to value,
                    "bootTimeMillis" to (System.currentTimeMillis() - SystemClock.elapsedRealtime()),
                )
            )
        }

        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.values.isEmpty()) return
                handler.post { finish(event.values[0].toInt()) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        // TYPE_STEP_COUNTER is an on-change sensor: it delivers its current
        // total on registration. The timeout only guards a device that never
        // reports at all — we return null (unknown) rather than a fake 0.
        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)
        handler.postDelayed({ finish(null) }, 4000)
    }
}
