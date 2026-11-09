package app.opendisplay.android;

import android.app.*;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.os.Build;
import android.os.IBinder;

/** Visible, user-stoppable foreground lifetime for an active connected session. */
public final class ReceiverKeepAliveService extends Service {
    static final String ACTION_STOP = "app.opendisplay.android.STOP_KEEP_ALIVE";
    @Override public void onCreate() {
        super.onCreate();
        promoteToForeground();
    }

    @Override public int onStartCommand(Intent intent, int flags, int id) {
        // Every startForegroundService request must be acknowledged before an
        // immediate disconnect can stop this instance. Commands arrive in order;
        // stopSelfResult also protects a newer start already queued by Android.
        promoteToForeground();
        if (intent != null && ACTION_STOP.equals(intent.getAction())) {
            stopSelfResult(id);
        }
        return START_NOT_STICKY;
    }

    private void promoteToForeground() {
        try {
            String channel = "receiver_session";
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(new NotificationChannel(
                        channel, "DisplayWeave connection", NotificationManager.IMPORTANCE_LOW));
            }
            PendingIntent open = PendingIntent.getActivity(this, 0,
                    new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
            Notification notification = new Notification.Builder(this, channel)
                    .setSmallIcon(android.R.drawable.stat_sys_upload)
                    .setContentTitle("DisplayWeave")
                    .setContentText("保持 Mac 连接，点按返回接收画面")
                    .setContentIntent(open)
                    .setOngoing(true)
                    .build();
            if (Build.VERSION.SDK_INT >= 29) {
                startForeground(1001, notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE);
            } else {
                startForeground(1001, notification);
            }
        } catch (RuntimeException error) {
            android.util.Log.w("DisplayWeave", "Keep-alive foreground promotion unavailable", error);
            stopSelf();
        }
    }

    @Override public IBinder onBind(Intent intent) { return null; }
}
