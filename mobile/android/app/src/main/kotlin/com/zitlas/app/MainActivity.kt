package com.zitlas.app

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine

/**
 * FlutterFragmentActivity (not FlutterActivity) because Health Connect's
 * permission flow goes through `registerForActivityResult`, which requires a
 * ComponentActivity — plain FlutterActivity extends android.app.Activity and
 * has no ActivityResult registry.
 */
class MainActivity : FlutterFragmentActivity() {
    private var stepTracker: StepTrackerPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // FlutterActivity extends ComponentActivity, so the Health Connect
        // permission contract can be registered against `this`. Registered
        // here rather than lazily on first use because
        // registerForActivityResult must be called before the activity
        // reaches STARTED — doing it on demand throws.
        stepTracker = StepTrackerPlugin(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        stepTracker?.dispose()
        stepTracker = null
        super.onDestroy()
    }
}
