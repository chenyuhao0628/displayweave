package app.opendisplay.android;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class TouchGestureCoordinator {
    public static final long HOLD_DELAY_MS = 120;
    private final double slop;
    private final double coordinateWidth;
    private final double coordinateHeight;
    private boolean pendingDown;
    private boolean activeTouch;
    private double downX;
    private double downY;
    private double lastX = 0.5;
    private double lastY = 0.5;

    public static final class Event {
        public final String phase;
        public final double x;
        public final double y;

        private Event(String phase, double x, double y) {
            this.phase = phase;
            this.x = x;
            this.y = y;
        }
    }

    public TouchGestureCoordinator(double slop) {
        this(slop, 1, 1);
    }

    public TouchGestureCoordinator(double slop, double coordinateWidth, double coordinateHeight) {
        this.slop = Math.max(0.0, slop);
        this.coordinateWidth = Math.max(1, coordinateWidth);
        this.coordinateHeight = Math.max(1, coordinateHeight);
    }

    public List<Event> begin(double x, double y) {
        pendingDown = true;
        activeTouch = false;
        downX = x;
        downY = y;
        lastX = x;
        lastY = y;
        return Collections.emptyList();
    }

    public List<Event> move(double x, double y) {
        lastX = x;
        lastY = y;
        if (pendingDown) {
            double dx = (x - downX) * coordinateWidth;
            double dy = (y - downY) * coordinateHeight;
            if (Math.hypot(dx, dy) < slop) {
                return Collections.emptyList();
            }
            pendingDown = false;
            activeTouch = true;
            List<Event> out = new ArrayList<>();
            out.add(new Event("began", downX, downY));
            out.add(new Event("moved", x, y));
            return out;
        }
        return activeTouch ? Collections.singletonList(new Event("moved", x, y))
                : Collections.emptyList();
    }

    public List<Event> commitHold() {
        if (!pendingDown) return Collections.emptyList();
        pendingDown = false;
        activeTouch = true;
        return Collections.singletonList(new Event("began", downX, downY));
    }

    public List<Event> end(double x, double y) {
        lastX = x;
        lastY = y;
        if (pendingDown) {
            pendingDown = false;
            List<Event> out = new ArrayList<>();
            out.add(new Event("began", downX, downY));
            out.add(new Event("ended", x, y));
            return out;
        }
        if (activeTouch) {
            activeTouch = false;
            return Collections.singletonList(new Event("ended", x, y));
        }
        return Collections.emptyList();
    }

    public List<Event> cancel() {
        pendingDown = false;
        if (activeTouch) {
            activeTouch = false;
            return Collections.singletonList(new Event("cancelled", lastX, lastY));
        }
        return Collections.emptyList();
    }
}
