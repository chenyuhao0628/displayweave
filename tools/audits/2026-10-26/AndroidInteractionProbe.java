package app.opendisplay.android;

/** Pure production gesture state; no Android UI or network is involved. */
public final class AndroidInteractionProbe {
    public static void main(String[] args) {
        TouchGestureCoordinator touch = new TouchGestureCoordinator(10.0 / 2560.0);
        int beforeRelease = touch.begin(0.5, 0.5).size();
        // Holding still produces no events; even repeated stationary MOVE does not commit down.
        for (int i = 0; i < 120; i++) beforeRelease += touch.move(0.5, 0.5).size();
        java.util.List<TouchGestureCoordinator.Event> release = touch.end(0.5, 0.5);
        if (beforeRelease != 0 || release.size() != 2
                || !release.get(0).phase.equals("began") || !release.get(1).phase.equals("ended")) {
            throw new AssertionError("Gesture policy changed; update audit interpretation");
        }
        System.out.println("Android stationary hold: 0 events before release; release emits began + ended together");
        System.out.println("Android two bounded FIFOs: " + FrameQueuePolicy.MAX_PENDING_FRAMES
                + " frames each; two full queues correspond to 400ms at 60fps (capacity arithmetic, not measured delay)");
    }
}
