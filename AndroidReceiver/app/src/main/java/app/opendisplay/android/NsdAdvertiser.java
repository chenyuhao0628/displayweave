package app.opendisplay.android;

import android.content.Context;
import android.net.nsd.NsdManager;
import android.net.nsd.NsdServiceInfo;
import android.net.wifi.WifiManager;
import android.os.Build;

public final class NsdAdvertiser {
    private final Context context;
    private final NsdManager nsdManager;
    private final WifiManager wifiManager;
    private final Listener listener;
    private NsdManager.RegistrationListener registration;
    private WifiManager.MulticastLock multicastLock;

    public interface Listener {
        void onNsdStatus(String status);
    }

    public NsdAdvertiser(Context context, Listener listener) {
        this.context = context.getApplicationContext();
        this.listener = listener;
        this.nsdManager = (NsdManager) this.context.getSystemService(Context.NSD_SERVICE);
        this.wifiManager = (WifiManager) this.context.getSystemService(Context.WIFI_SERVICE);
    }

    public void start(String serviceName, String installId, int port, boolean secure) {
        stop();
        if (wifiManager != null) {
            multicastLock = wifiManager.createMulticastLock("OpenDisplayAndroidNsd");
            multicastLock.setReferenceCounted(false);
            multicastLock.acquire();
        }

        NsdServiceInfo info = new NsdServiceInfo();
        info.setServiceName(serviceName);
        info.setServiceType("_opensidecar._tcp.");
        info.setPort(port);
        if (Build.VERSION.SDK_INT >= 21) {
            info.setAttribute("id", installId);
            if (secure) info.setAttribute("security", "tls-v1");
        }

        registration = new NsdManager.RegistrationListener() {
            @Override
            public void onServiceRegistered(NsdServiceInfo serviceInfo) {
                if (registration != this) return;
                listener.onNsdStatus("已广播：" + serviceInfo.getServiceName());
            }

            @Override
            public void onRegistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                if (registration != this) return;
                listener.onNsdStatus("广播失败：" + errorCode);
            }

            @Override
            public void onServiceUnregistered(NsdServiceInfo serviceInfo) {
                if (registration != this) return;
                listener.onNsdStatus("广播已停止");
            }

            @Override
            public void onUnregistrationFailed(NsdServiceInfo serviceInfo, int errorCode) {
                if (registration != this) return;
                listener.onNsdStatus("停止广播失败：" + errorCode);
            }
        };
        nsdManager.registerService(info, NsdManager.PROTOCOL_DNS_SD, registration);
    }

    public void stop() {
        NsdManager.RegistrationListener activeRegistration = registration;
        registration = null;
        if (activeRegistration != null) {
            try {
                nsdManager.unregisterService(activeRegistration);
            } catch (IllegalArgumentException ignored) {
                // Already unregistered by the framework.
            }
        }
        if (multicastLock != null && multicastLock.isHeld()) {
            multicastLock.release();
        }
        multicastLock = null;
    }
}
