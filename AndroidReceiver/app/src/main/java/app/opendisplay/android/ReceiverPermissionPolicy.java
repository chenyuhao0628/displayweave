package app.opendisplay.android;

final class ReceiverPermissionPolicy {
    private ReceiverPermissionPolicy() {}

    static boolean canStartTcpServer(boolean nearbyWifiGranted) {
        return true;
    }

    static boolean shouldAdvertiseWifi(boolean nearbyWifiGranted) {
        return nearbyWifiGranted;
    }
}
