package com.zitlas.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.Calendar

private const val TAG = "ZitlasSteps"

/**
 * Captures the hardware step counter AT LOCAL MIDNIGHT, with ZITLAS closed.
 *
 * WHY THIS EXISTS. TYPE_STEP_COUNTER reports a running total since boot and
 * nothing else — no timestamps, no history. So the only way to know how many
 * of those steps belonged to yesterday is to have read the counter at the
 * moment the day ended. If nobody reads it at midnight, the steps taken
 * between the last time the app was opened and 00:00 are unattributable: they
 * either vanish from yesterday or get credited to today, and both are wrong.
 * (Health Connect has no such problem — its records are timestamped and can be
 * totalled after the fact, which is why it stays the preferred source.)
 *
 * WHY A RECEIVER AND NOT A SERVICE OR A DART ISOLATE. This needs about 200ms
 * of work once a day. A foreground service would put a permanent notification
 * in the shade and burn battery for 24 hours to do it; a WorkManager Dart task
 * would spin up a whole Flutter engine and is subject to a 15-minute scheduling
 * floor plus Doze batching, so it cannot be relied on to land at 00:00. An
 * AlarmManager broadcast into plain Kotlin costs nothing until it fires and
 * lands on time.
 *
 * The reading is written into the SAME SharedPreferences file the Flutter side
 * uses (`FlutterSharedPreferences`, keys prefixed `flutter.`), so Dart picks it
 * up on the next launch with no IPC and no engine involved.
 */
object StepDayBoundary {

    /** Matches shared_preferences' Android backing file and key prefix. */
    private const val PREFS_FILE = "FlutterSharedPreferences"
    private const val PREFIX = "flutter."

    /** The captured midnight reading, consumed by Dart. */
    const val KEY_BOUNDARY = "${PREFIX}zitlas_step_boundary"

    /** Mirrors StepTrackingService's own key, so Kotlin never reads a day the athlete hasn't enabled. */
    private const val KEY_ENABLED = "${PREFIX}zitlas_step_tracking_enabled"

    private const val REQUEST_CODE = 8801
    const val ACTION_MIDNIGHT = "com.zitlas.app.STEP_DAY_BOUNDARY"

    fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_FILE, Context.MODE_PRIVATE)

    fun isTrackingEnabled(context: Context): Boolean =
        try {
            prefs(context).getBoolean(KEY_ENABLED, false)
        } catch (e: Throwable) {
            false
        }

    /**
     * Arms the next local-midnight capture.
     *
     * Idempotent: the same request code replaces any existing alarm rather than
     * stacking a second one. Called on app start, after every capture, and from
     * the boot receiver.
     */
    fun scheduleNext(context: Context) {
        val alarmManager =
            context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return

        // A few seconds PAST midnight, not exactly on it: at 00:00:00.000 the
        // calendar date the reading gets filed under is ambiguous by a
        // millisecond of clock skew, and being five seconds late costs nothing.
        val next = Calendar.getInstance().apply {
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 5)
            set(Calendar.MILLISECOND, 0)
        }

        val intent = Intent(context, StepDayBoundaryReceiver::class.java).apply {
            action = ACTION_MIDNIGHT
        }
        val pending = PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        // Exact where allowed, inexact where it isn't. A day boundary that
        // lands a few minutes late still attributes almost every step
        // correctly; refusing to schedule at all because the exact-alarm
        // permission is missing would lose the whole day.
        val canExact = Build.VERSION.SDK_INT < 31 || alarmManager.canScheduleExactAlarms()
        try {
            if (canExact) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, next.timeInMillis, pending,
                )
            } else {
                alarmManager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP, next.timeInMillis, pending,
                )
            }
        } catch (e: SecurityException) {
            alarmManager.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, next.timeInMillis, pending,
            )
        }
    }

    /**
     * Reads TYPE_STEP_COUNTER once and hands the value to [onRead] (null if the
     * sensor is unavailable, unpermitted, or silent).
     *
     * TYPE_STEP_COUNTER is an on-change sensor and normally delivers its
     * current total the moment a listener registers, but not every device does
     * so promptly on an idle handset — hence the timeout and the honest null.
     */
    fun readCounter(context: Context, timeoutMs: Long = 6000, onRead: (Int?) -> Unit) {
        if (Build.VERSION.SDK_INT >= 29 &&
            context.checkSelfPermission(android.Manifest.permission.ACTIVITY_RECOGNITION) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            onRead(null)
            return
        }
        val sm = context.getSystemService(Context.SENSOR_SERVICE) as? SensorManager
        val sensor = sm?.getDefaultSensor(Sensor.TYPE_STEP_COUNTER)
        if (sm == null || sensor == null) {
            onRead(null)
            return
        }

        val handler = Handler(Looper.getMainLooper())
        var settled = false
        var listener: SensorEventListener? = null

        fun finish(value: Int?) {
            if (settled) return
            settled = true
            listener?.let { runCatching { sm.unregisterListener(it) } }
            onRead(value)
        }

        listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.values.isEmpty()) return
                handler.post { finish(event.values[0].toInt()) }
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        sm.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_FASTEST)
        handler.postDelayed({ finish(null) }, timeoutMs)
    }

    /**
     * Stores the captured reading as JSON for Dart.
     *
     * `dayKey` is the day that just ENDED — the reading is that day's closing
     * total, and simultaneously the opening origin for the day now starting.
     */
    fun writeBoundary(context: Context, dayKey: String, cumulative: Int) {
        val bootTimeMillis = System.currentTimeMillis() - SystemClock.elapsedRealtime()
        val json = """{"dayKey":"$dayKey","cumulative":$cumulative,""" +
            """"bootTimeMillis":$bootTimeMillis,"capturedAt":${System.currentTimeMillis()}}"""
        prefs(context).edit().putString(KEY_BOUNDARY, json).commit()
    }

    /** Local `YYYY-MM-DD` for the day that just ended (i.e. yesterday, at 00:00:05). */
    fun previousDayKey(): String {
        val c = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, -1) }
        return "%04d-%02d-%02d".format(
            c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH),
        )
    }
}

/**
 * Fires at 00:00:05 local. Captures the closing counter value for the day that
 * just ended and re-arms itself for the next one.
 */
class StepDayBoundaryReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val app = context.applicationContext
        Log.i(TAG, "midnight boundary fired")
        // Always re-arm FIRST. If the sensor read below fails or the process is
        // killed mid-flight, tomorrow's capture must still be scheduled —
        // otherwise one bad night silently ends daily rollover forever.
        StepDayBoundary.scheduleNext(app)

        if (!StepDayBoundary.isTrackingEnabled(app)) return

        val pending = goAsync()
        val dayKey = StepDayBoundary.previousDayKey()
        StepDayBoundary.readCounter(app) { value ->
            try {
                if (value != null) {
                    StepDayBoundary.writeBoundary(app, dayKey, value)
                    Log.i(TAG, "day $dayKey closed at counter=$value")
                } else {
                    // The sensor stayed silent. Nothing is written, and nothing
                    // is guessed — Health Connect (where present) can still
                    // total the day retrospectively, and a fabricated boundary
                    // would corrupt both days rather than lose one.
                    Log.w(TAG, "day $dayKey — step counter unreadable, no boundary written")
                }
            } finally {
                pending.finish()
            }
        }
    }
}

/**
 * Re-arms the midnight capture after a restart.
 *
 * AlarmManager forgets every alarm on reboot, so without this the day boundary
 * is never captured again until the athlete happens to open the app.
 */
class StepBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        Log.i(TAG, "boot/replace received: $action")
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) {
            return
        }
        StepDayBoundary.scheduleNext(context.applicationContext)
        Log.i(TAG, "midnight capture re-armed after $action")
    }
}
