package com.ryanheise.audioservice;

import android.app.NotificationManager;
import android.content.Context;
import android.support.v4.media.session.MediaSessionCompat;

import androidx.core.app.ServiceCompat;

/**
 * Cleans up the media notification when a playback session ends.
 *
 * <p>audio_service runs a bound {@code MediaBrowserService}. {@code
 * AudioService.stop()} only calls {@code stopSelf()}, which cannot destroy a
 * service while the activity is still bound, and cancelling a foreground
 * notification has no effect while the service is still foreground. The result
 * is a stale, non-dismissible media card after the user stops playback.
 *
 * <p>This helper lives in audio_service's package so it can read the
 * package-private {@code AudioService.instance} without reflection. It drops
 * the foreground state explicitly, which removes the notification for good.
 */
public final class SoundisleAudioBridge {
    // audio_service uses this fixed id for the media notification.
    private static final int NOTIFICATION_ID = 1124;

    private static AudioService watchedService;

    private SoundisleAudioBridge() {}

    /** Drops the foreground state and removes the media notification. */
    public static boolean stopSession(Context context) {
        AudioService service = AudioService.instance;
        if (service == null) {
            return false;
        }
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE);
        NotificationManager manager =
                (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (manager != null) {
            manager.cancel(NOTIFICATION_ID);
        }
        // Do NOT call stopService here: audio_service disposes the Flutter
        // engine from AudioService.onDestroy, which would blank the activity.
        // The service is bound to the activity, so it stays alive and idle.
        return true;
    }

    /**
     * Watches the media session so a stop triggered from the notification
     * (which never reaches the Dart isolate) also clears the notification and
     * lets the app reset its playback UI.
     */
    public static boolean watchSession(Context context, Runnable onStopped) {
        final AudioService service = AudioService.instance;
        if (service == null) {
            // The service is created asynchronously after playback starts, so
            // the caller retries until this returns true.
            return false;
        }
        if (watchedService == service) {
            return true;
        }
        final MediaSessionCompat session;
        try {
            java.lang.reflect.Field field =
                    AudioService.class.getDeclaredField("mediaSession");
            field.setAccessible(true);
            session = (MediaSessionCompat) field.get(service);
        } catch (Exception error) {
            return false;
        }
        if (session == null) {
            return false;
        }
        final Context appContext = context.getApplicationContext();
        session.addOnActiveChangeListener(new MediaSessionCompat.OnActiveChangeListener() {
            @Override
            public void onActiveChanged() {
                if (!session.isActive()) {
                    stopSession(appContext);
                    onStopped.run();
                }
            }
        });
        watchedService = service;
        return true;
    }
}
