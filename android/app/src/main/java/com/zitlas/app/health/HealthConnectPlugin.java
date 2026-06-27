package com.zitlas.app.health;

import android.content.Intent;
import android.util.Log;

import androidx.activity.result.ActivityResult;
import androidx.health.connect.client.HealthConnectClient;
import androidx.health.connect.client.PermissionController;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.ActivityCallback;
import com.getcapacitor.annotation.CapacitorPlugin;

@CapacitorPlugin(name = "HealthConnect")
public class HealthConnectPlugin extends Plugin {

    private static final String TAG = "HealthConnectPlugin";

    // ── Availability ──────────────────────────────────────────────────────────

    @PluginMethod
    public void isAvailable(PluginCall call) {
        int status = HealthConnectManager.getSdkStatus(getContext());
        JSObject result = new JSObject();
        result.put("available", status == HealthConnectClient.SDK_AVAILABLE);
        result.put("status", status);
        call.resolve(result);
    }

    // ── Permissions ───────────────────────────────────────────────────────────

    /**
     * Launches the Health Connect permission screen. Resolves with
     * { permissionGranted: true/false } once the user returns.
     */
    @PluginMethod
    public void requestPermissions(PluginCall call) {
        if (!HealthConnectManager.isAvailable(getContext())) {
            JSObject result = new JSObject();
            result.put("available", false);
            call.resolve(result);
            return;
        }
        try {
            @SuppressWarnings("unchecked")
            Intent intent = PermissionController.createRequestPermissionResultContract()
                    .createIntent(getContext(), HealthConnectManager.PERMISSIONS);
            startActivityForResult(call, intent, "onPermissionResult");
        } catch (Exception e) {
            Log.e(TAG, "requestPermissions failed", e);
            call.reject("Failed to launch permission screen: " + e.getMessage());
        }
    }

    @ActivityCallback
    private void onPermissionResult(PluginCall call, ActivityResult result) {
        if (call == null) return;
        HealthConnectManager.checkPermissions(getContext(), new HealthConnectManager.PermissionCallback() {
            @Override
            public void onResult(boolean allGranted) {
                JSObject res = new JSObject();
                res.put("permissionGranted", allGranted);
                call.resolve(res);
            }

            @Override
            public void onError(String message) {
                call.reject(message);
            }
        });
    }

    // ── Step count ────────────────────────────────────────────────────────────

    /**
     * Returns today's step count: { steps: 6162 }
     * Returns { available: false } if Health Connect is not installed.
     */
    @PluginMethod
    public void getTodaySteps(PluginCall call) {
        if (!HealthConnectManager.isAvailable(getContext())) {
            JSObject result = new JSObject();
            result.put("available", false);
            call.resolve(result);
            return;
        }
        HealthConnectManager.getTodayActivity(getContext(), new HealthConnectManager.ActivityCallback() {
            @Override
            public void onSuccess(int steps, int caloriesBurned, double distanceKm, int activeMinutes) {
                JSObject result = new JSObject();
                result.put("steps", steps);
                call.resolve(result);
            }

            @Override
            public void onError(String message) {
                Log.e(TAG, "getTodaySteps error: " + message);
                call.reject(message);
            }
        });
    }

    // ── Full activity data ────────────────────────────────────────────────────

    /**
     * Returns today's full activity summary:
     * { today_steps, calories_burned, distance_km, active_minutes }
     *
     * Returns { available: false }    if Health Connect is not installed.
     * Returns { permissionGranted: false } if permissions were denied.
     */
    @PluginMethod
    public void getTodayActivity(PluginCall call) {
        if (!HealthConnectManager.isAvailable(getContext())) {
            JSObject result = new JSObject();
            result.put("available", false);
            call.resolve(result);
            return;
        }
        HealthConnectManager.getTodayActivity(getContext(), new HealthConnectManager.ActivityCallback() {
            @Override
            public void onSuccess(int steps, int caloriesBurned, double distanceKm, int activeMinutes) {
                JSObject result = new JSObject();
                result.put("today_steps", steps);
                result.put("calories_burned", caloriesBurned);
                result.put("distance_km", distanceKm);
                result.put("active_minutes", activeMinutes);
                call.resolve(result);
            }

            @Override
            public void onError(String message) {
                Log.e(TAG, "getTodayActivity error: " + message);
                if (message != null && message.toLowerCase().contains("permission")) {
                    JSObject result = new JSObject();
                    result.put("permissionGranted", false);
                    call.resolve(result);
                } else {
                    call.reject(message);
                }
            }
        });
    }
}
