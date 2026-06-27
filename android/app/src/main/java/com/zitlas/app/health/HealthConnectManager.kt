package com.zitlas.app.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.time.Duration
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.roundToInt

/**
 * Kotlin helper for Health Connect. All coroutine calls live here so the Java
 * Capacitor plugin stays free of Kotlin-suspend complexity. Each method
 * accepts a callback interface that the Java side implements.
 */
object HealthConnectManager {

    /** Full set of read permissions the plugin needs. */
    @JvmField
    val PERMISSIONS: Set<String> = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
    )

    // ── Availability ─────────────────────────────────────────────────────────

    @JvmStatic
    fun getSdkStatus(context: Context): Int =
        HealthConnectClient.getSdkStatus(context)

    @JvmStatic
    fun isAvailable(context: Context): Boolean =
        HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE

    // ── Permission check ─────────────────────────────────────────────────────

    interface PermissionCallback {
        fun onResult(allGranted: Boolean)
        fun onError(message: String)
    }

    @JvmStatic
    fun checkPermissions(context: Context, callback: PermissionCallback) {
        val client = clientOrError(context, callback) ?: return
        CoroutineScope(Dispatchers.IO).launch {
            try {
                val granted = client.permissionController.getGrantedPermissions()
                callback.onResult(PERMISSIONS.all { it in granted })
            } catch (e: Exception) {
                callback.onError(e.message ?: "Permission check failed")
            }
        }
    }

    // ── Activity data ─────────────────────────────────────────────────────────

    interface ActivityCallback {
        fun onSuccess(steps: Int, caloriesBurned: Int, distanceKm: Double, activeMinutes: Int)
        fun onError(message: String)
    }

    @JvmStatic
    fun getTodayActivity(context: Context, callback: ActivityCallback) {
        val client = clientOrError(context, object : PermissionCallback {
            override fun onResult(allGranted: Boolean) {}
            override fun onError(message: String) = callback.onError(message)
        }) ?: return

        CoroutineScope(Dispatchers.IO).launch {
            try {
                val now = ZonedDateTime.now(ZoneId.systemDefault())
                val startOfDay = now.toLocalDate().atStartOfDay(ZoneId.systemDefault())
                val timeRange = TimeRangeFilter.between(
                    startOfDay.toInstant(),
                    now.toInstant()
                )

                // Single aggregate call for steps + calories + distance
                val agg = client.aggregate(
                    AggregateRequest(
                        metrics = setOf(
                            StepsRecord.COUNT_TOTAL,
                            TotalCaloriesBurnedRecord.ENERGY_TOTAL,
                            DistanceRecord.DISTANCE_TOTAL,
                        ),
                        timeRangeFilter = timeRange
                    )
                )

                val steps = agg[StepsRecord.COUNT_TOTAL]?.toLong()?.toInt() ?: 0
                val calories = agg[TotalCaloriesBurnedRecord.ENERGY_TOTAL]
                    ?.inKilocalories?.roundToInt() ?: 0
                val distanceKm = (agg[DistanceRecord.DISTANCE_TOTAL]
                    ?.inMeters ?: 0.0).let { m ->
                    (m / 100.0).roundToInt().toDouble() / 10.0  // 1 decimal place
                }

                // Sum exercise session durations for active minutes
                val exercises = client.readRecords(
                    ReadRecordsRequest(
                        recordType = ExerciseSessionRecord::class,
                        timeRangeFilter = timeRange
                    )
                )
                val activeMinutes = exercises.records
                    .sumOf { Duration.between(it.startTime, it.endTime).toMinutes() }
                    .toInt()

                callback.onSuccess(steps, calories, distanceKm, activeMinutes)

            } catch (e: Exception) {
                callback.onError(e.message ?: "Failed to read activity data")
            }
        }
    }

    // ── Internal helpers ─────────────────────────────────────────────────────

    private fun clientOrError(context: Context, callback: PermissionCallback): HealthConnectClient? {
        return try {
            HealthConnectClient.getOrCreate(context)
        } catch (e: Exception) {
            callback.onError(e.message ?: "Failed to create HealthConnectClient")
            null
        }
    }

    private fun clientOrError(context: Context, callback: ActivityCallback): HealthConnectClient? {
        return try {
            HealthConnectClient.getOrCreate(context)
        } catch (e: Exception) {
            callback.onError(e.message ?: "Failed to create HealthConnectClient")
            null
        }
    }
}
