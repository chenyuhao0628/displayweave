package app.opendisplay.android;

import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.os.Build;
import android.os.PowerManager;

/** Point-in-time thermal and battery evidence; unavailable readings remain null. */
public final class AndroidPowerMetrics {
    public static final class Snapshot {
        public final Integer thermalStatus;
        public final Boolean powerSaver;
        public final Double batteryTemperature;
        public final Integer batteryLevel;
        public final Boolean charging;

        Snapshot(Integer thermalStatus, Boolean powerSaver,
                 Double batteryTemperature, Integer batteryLevel,
                 Boolean charging) {
            this.thermalStatus = thermalStatus;
            this.powerSaver = powerSaver;
            this.batteryTemperature = batteryTemperature;
            this.batteryLevel = batteryLevel;
            this.charging = charging;
        }
    }

    private final Context context;
    private final PowerManager powerManager;

    public AndroidPowerMetrics(Context context) {
        Context applicationContext = context.getApplicationContext();
        this.context = applicationContext == null ? context : applicationContext;
        this.powerManager = (PowerManager) context.getSystemService(Context.POWER_SERVICE);
    }

    public Snapshot sample() {
        Integer thermalStatus = null;
        Boolean powerSaver = null;
        if (powerManager != null) {
            try {
                powerSaver = powerManager.isPowerSaveMode();
            } catch (RuntimeException ignored) {
                // Keep unavailable values null rather than manufacturing zero/false.
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                try {
                    thermalStatus = powerManager.getCurrentThermalStatus();
                } catch (RuntimeException ignored) {
                    // Some vendor implementations can reject or omit this reading.
                }
            }
        }

        Integer temperatureTenthsC = null;
        Integer level = null;
        Integer scale = null;
        Boolean charging = null;
        try {
            Intent battery = context.registerReceiver(
                    null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));
            if (battery != null) {
                int rawTemperature = battery.getIntExtra(
                        BatteryManager.EXTRA_TEMPERATURE, Integer.MIN_VALUE);
                if (rawTemperature != Integer.MIN_VALUE) {
                    temperatureTenthsC = rawTemperature;
                }
                int rawLevel = battery.getIntExtra(
                        BatteryManager.EXTRA_LEVEL, Integer.MIN_VALUE);
                int rawScale = battery.getIntExtra(
                        BatteryManager.EXTRA_SCALE, Integer.MIN_VALUE);
                if (rawLevel != Integer.MIN_VALUE) level = rawLevel;
                if (rawScale != Integer.MIN_VALUE) scale = rawScale;
                int status = battery.getIntExtra(
                        BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN);
                if (status != BatteryManager.BATTERY_STATUS_UNKNOWN) {
                    charging = status == BatteryManager.BATTERY_STATUS_CHARGING
                            || status == BatteryManager.BATTERY_STATUS_FULL;
                }
            }
        } catch (RuntimeException ignored) {
            // Battery broadcasts are best-effort metrics, never a streaming dependency.
        }
        return fromReadings(
                thermalStatus, powerSaver, temperatureTenthsC, level, scale, charging);
    }

    static Snapshot fromReadings(
            Integer thermalStatus, Boolean powerSaver,
            Integer temperatureTenthsC, Integer level, Integer scale,
            Boolean charging) {
        Double temperatureC = temperatureTenthsC == null
                ? null : temperatureTenthsC / 10.0;
        Integer levelPercent = null;
        if (level != null && scale != null && level >= 0 && scale > 0) {
            levelPercent = Math.max(0, Math.min(
                    100, (int) Math.round(level * 100.0 / scale)));
        }
        return new Snapshot(
                thermalStatus, powerSaver, temperatureC, levelPercent, charging);
    }
}
