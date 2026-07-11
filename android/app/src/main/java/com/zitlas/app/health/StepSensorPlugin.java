package com.zitlas.app.health;

import android.Manifest;
import android.content.Context;
import android.hardware.Sensor;
import android.hardware.SensorEvent;
import android.hardware.SensorEventListener;
import android.hardware.SensorManager;
import android.os.Build;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.PermissionState;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;
import com.getcapacitor.annotation.PermissionCallback;

/**
 * Hardware step-counter fallback for devices WITHOUT Health Connect.
 *
 * TYPE_STEP_COUNTER is a low-power hardware counter that accumulates steps
 * since the last device BOOT, counting continuously in the background with
 * no app process, no service, and no battery cost to us — the same counter
 * Google Fit reads. The JS side (assets/js/step-sensor.js) persists a
 * baseline and turns the cumulative value into a daily delta, which also
 * makes screen-lock/minimized/rebooted tracking work: we simply read the
 * counter's new value whenever the app is next opened.
 *
 * Two read modes:
 *   readCumulative()  — one-shot: register, take first event, unregister.
 *   startWatch()      — foreground-only live updates; every sensor event is
 *                       forwarded to JS as a "step" plugin event. stopWatch()
 *                       (called on pause from JS) unregisters the listener so
 *                       nothing runs while the app is backgrounded.
 *
 * ACTIVITY_RECOGNITION is required for this sensor on Android 10+ (API 29).
 */
@CapacitorPlugin(
    name = "StepSensor",
    permissions = @Permission(
        alias = "activity",
        strings = { Manifest.permission.ACTIVITY_RECOGNITION }
    )
)
public class StepSensorPlugin extends Plugin implements SensorEventListener {

    private static final String TAG = "StepSensorPlugin";

    private SensorManager sensorManager;
    private Sensor stepSensor;
    private boolean watching = false;

    /** One-shot listener for readCumulative(); nulled after first event. */
    private SensorEventListener oneShotListener = null;

    private SensorManager sm() {
        if (sensorManager == null) {
            sensorManager = (SensorManager) getContext().getSystemService(Context.SENSOR_SERVICE);
        }
        return sensorManager;
    }

    private Sensor sensor() {
        if (stepSensor == null && sm() != null) {
            stepSensor = sm().getDefaultSensor(Sensor.TYPE_STEP_COUNTER);
        }
        return stepSensor;
    }

    private boolean hasActivityPermission() {
        // Runtime permission only exists on API 29+; earlier versions grant at install.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return true;
        return getPermissionState("activity") == PermissionState.GRANTED;
    }

    // ── Availability ─────────────────────────────────────────────────────────

    @PluginMethod
    public void isAvailable(PluginCall call) {
        JSObject res = new JSObject();
        res.put("available", sensor() != null);
        res.put("permissionGranted", hasActivityPermission());
        call.resolve(res);
    }

    // ── Permission ───────────────────────────────────────────────────────────

    @PluginMethod
    public void requestPermission(PluginCall call) {
        if (hasActivityPermission()) {
            JSObject res = new JSObject();
            res.put("granted", true);
            call.resolve(res);
            return;
        }
        requestPermissionForAlias("activity", call, "activityPermissionCallback");
    }

    @PermissionCallback
    private void activityPermissionCallback(PluginCall call) {
        JSObject res = new JSObject();
        res.put("granted", hasActivityPermission());
        call.resolve(res);
    }

    // ── One-shot cumulative read ─────────────────────────────────────────────

    /**
     * Resolves { available, granted, cumulative } where `cumulative` is the
     * hardware counter's steps-since-boot. The JS baseline logic converts
     * this to a daily count. A device that has taken zero steps since boot
     * may never deliver an event — a 3s timeout resolves with cumulative:-1
     * so callers can treat it as "no reading yet" rather than hanging.
     */
    @PluginMethod
    public void readCumulative(PluginCall call) {
        if (sensor() == null) {
            JSObject res = new JSObject();
            res.put("available", false);
            call.resolve(res);
            return;
        }
        if (!hasActivityPermission()) {
            JSObject res = new JSObject();
            res.put("available", true);
            res.put("granted", false);
            call.resolve(res);
            return;
        }

        final boolean[] done = { false };
        final SensorEventListener listener = new SensorEventListener() {
            @Override
            public void onSensorChanged(SensorEvent event) {
                synchronized (done) {
                    if (done[0]) return;
                    done[0] = true;
                }
                sm().unregisterListener(this);
                JSObject res = new JSObject();
                res.put("available", true);
                res.put("granted", true);
                res.put("cumulative", (long) event.values[0]);
                call.resolve(res);
            }

            @Override
            public void onAccuracyChanged(Sensor s, int accuracy) {}
        };

        boolean registered = sm().registerListener(listener, sensor(), SensorManager.SENSOR_DELAY_NORMAL);
        if (!registered) {
            JSObject res = new JSObject();
            res.put("available", false);
            call.resolve(res);
            return;
        }

        // Timeout: some devices only deliver the first event on the next step.
        getBridge().getActivity().getWindow().getDecorView().postDelayed(() -> {
            synchronized (done) {
                if (done[0]) return;
                done[0] = true;
            }
            sm().unregisterListener(listener);
            JSObject res = new JSObject();
            res.put("available", true);
            res.put("granted", true);
            res.put("cumulative", -1L);
            call.resolve(res);
        }, 3000);
    }

    // ── Foreground live watch ────────────────────────────────────────────────

    @PluginMethod
    public void startWatch(PluginCall call) {
        JSObject res = new JSObject();
        if (sensor() == null || !hasActivityPermission()) {
            res.put("watching", false);
            call.resolve(res);
            return;
        }
        if (!watching) {
            watching = sm().registerListener(this, sensor(), SensorManager.SENSOR_DELAY_UI);
            Log.d(TAG, "live watch " + (watching ? "started" : "failed to start"));
        }
        res.put("watching", watching);
        call.resolve(res);
    }

    @PluginMethod
    public void stopWatch(PluginCall call) {
        if (watching) {
            sm().unregisterListener(this);
            watching = false;
            Log.d(TAG, "live watch stopped");
        }
        JSObject res = new JSObject();
        res.put("watching", false);
        call.resolve(res);
    }

    @Override
    public void onSensorChanged(SensorEvent event) {
        JSObject data = new JSObject();
        data.put("cumulative", (long) event.values[0]);
        notifyListeners("step", data);
    }

    @Override
    public void onAccuracyChanged(Sensor s, int accuracy) {}

    /** Belt-and-braces: never leave a listener running when the app pauses. */
    @Override
    protected void handleOnPause() {
        if (watching) {
            sm().unregisterListener(this);
            watching = false;
        }
        super.handleOnPause();
    }
}
