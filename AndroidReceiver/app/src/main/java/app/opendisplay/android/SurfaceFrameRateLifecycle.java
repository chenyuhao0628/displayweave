package app.opendisplay.android;

public final class SurfaceFrameRateLifecycle {
    public interface Actions {
        void apply(int fps, String reason);
        void clear(String reason);
    }

    private final Actions actions;
    private boolean foreground;
    private boolean surfaceAvailable;
    private boolean applied;
    private boolean streaming;
    private int requestedFps = 60;

    public SurfaceFrameRateLifecycle(Actions actions) {
        this.actions = actions;
    }

    public void onResume() {
        foreground = true;
        applyIfReady("foregroundResume");
    }

    public void onPause() {
        foreground = false;
        clearIfApplied("appBackground");
    }

    public void onSurfaceCreated() {
        surfaceAvailable = true;
        applyIfReady("surfaceCreated");
    }

    public void onSurfaceChanged() {
        applyIfReady("surfaceChanged");
    }

    public void onSurfaceDestroyed() {
        clearIfApplied("surfaceDestroyed");
        surfaceAvailable = false;
    }

    public void onStreamConfig(int fps) {
        requestedFps = RefreshRateController.sanitizeFps(fps);
        applyIfReady("streamConfig");
    }

    public void onDecoderRebuild() {
        applyIfReady("decoderRebuild");
    }

    public void onStreamingStarted() {
        if (streaming) {
            return;
        }
        streaming = true;
        applyIfReady("streamingStarted");
    }

    public void onStreamingStopped() {
        if (!streaming && !applied) {
            return;
        }
        streaming = false;
        clearIfApplied("streamingStopped");
    }

    public void onDestroy() {
        clearIfApplied("activityDestroyed");
        foreground = false;
        surfaceAvailable = false;
        streaming = false;
    }

    private void applyIfReady(String reason) {
        if (!foreground || !surfaceAvailable) {
            return;
        }
        actions.apply(requestedFps, reason);
        applied = true;
    }

    private void clearIfApplied(String reason) {
        if (!applied) {
            return;
        }
        actions.clear(reason);
        applied = false;
    }
}
