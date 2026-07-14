package app.opendisplay.android;

import java.util.Locale;

public enum WifiLowLatencyMode {
    AUTO("auto", "自动"),
    ON("on", "开启"),
    OFF("off", "关闭");

    public final String key;
    public final String label;

    WifiLowLatencyMode(String key, String label) {
        this.key = key;
        this.label = label;
    }

    public boolean requestsLowLatency() {
        return this != OFF;
    }

    public static WifiLowLatencyMode fromStoredValue(String value) {
        if (value != null) {
            String normalized = value.toLowerCase(Locale.US);
            for (WifiLowLatencyMode mode : values()) {
                if (mode.key.equals(normalized)) {
                    return mode;
                }
            }
        }
        return AUTO;
    }
}
