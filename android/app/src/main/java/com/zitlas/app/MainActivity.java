package com.zitlas.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
import com.zitlas.app.health.HealthConnectPlugin;
import com.zitlas.app.health.StepSensorPlugin;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(HealthConnectPlugin.class);
        registerPlugin(StepSensorPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
