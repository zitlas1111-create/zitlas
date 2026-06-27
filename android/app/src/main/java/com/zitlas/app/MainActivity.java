package com.zitlas.app;

import android.os.Bundle;
import com.getcapacitor.BridgeActivity;
import com.zitlas.app.health.HealthConnectPlugin;

public class MainActivity extends BridgeActivity {
    @Override
    public void onCreate(Bundle savedInstanceState) {
        registerPlugin(HealthConnectPlugin.class);
        super.onCreate(savedInstanceState);
    }
}
