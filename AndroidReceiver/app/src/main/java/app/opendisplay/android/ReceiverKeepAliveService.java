package app.opendisplay.android;

import android.app.*;
import android.content.Intent;
import android.os.IBinder;

/** Visible, user-stoppable foreground lifetime for the receiver session. */
public final class ReceiverKeepAliveService extends Service {
    @Override public void onCreate() {
        super.onCreate();
        String channel = "receiver_session";
        getSystemService(NotificationManager.class).createNotificationChannel(
                new NotificationChannel(channel, "DisplayWeave connection", NotificationManager.IMPORTANCE_LOW));
        PendingIntent open = PendingIntent.getActivity(this, 0,
                new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
        startForeground(1001, new Notification.Builder(this, channel)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setContentTitle("DisplayWeave")
                .setContentText("保持 Mac 连接，点按返回接收画面")
                .setContentIntent(open).setOngoing(true).build());
    }
    @Override public int onStartCommand(Intent intent, int flags, int id) {
        return START_NOT_STICKY;
    }
    @Override public IBinder onBind(Intent intent) { return null; }
}
