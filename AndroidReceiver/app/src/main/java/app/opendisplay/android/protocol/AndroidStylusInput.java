package app.opendisplay.android.protocol;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Pure-Java, host-testable stylus & tablet hover/pressure/tilt translator for
 * DisplayWeave {@code pencil-v1}, {@code pencil-v2}, and {@code pencilAction}.
 * Matches {@code Shared/PencilProtocol.swift} and {@code Shared/PencilActions.swift} byte-for-byte.
 */
public final class AndroidStylusInput {
    public static final String CAPABILITY_V1 = "pencil-v1";
    public static final String CAPABILITY_V2 = "pencil-v2";

    // Android MotionEvent constants (mirrored here to keep protocol pure-Java & host-testable)
    public static final int ACTION_DOWN = 0;
    public static final int ACTION_UP = 1;
    public static final int ACTION_MOVE = 2;
    public static final int ACTION_CANCEL = 3;
    public static final int ACTION_HOVER_MOVE = 7;
    public static final int ACTION_HOVER_ENTER = 9;
    public static final int ACTION_HOVER_EXIT = 10;

    public static final int TOOL_TYPE_FINGER = 1;
    public static final int TOOL_TYPE_STYLUS = 2;
    public static final int TOOL_TYPE_MOUSE = 3;
    public static final int TOOL_TYPE_ERASER = 4;

    public static final int BUTTON_STYLUS_PRIMARY = 32;
    public static final int BUTTON_STYLUS_SECONDARY = 64;

    public static final long MAX_SAFE_SEQUENCE = 9_007_199_254_740_991L;

    private static final double TWO_PI = 2.0 * Math.PI;
    private static final double HALF_PI = Math.PI / 2.0;
    private static final Pattern UUID_PATTERN = Pattern.compile(
            "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$");
    private static final Pattern ACTION_STATUS_FIELD =
            Pattern.compile("\"pencilActionStatus\"\\s*:\\s*\"([^\"]*)\"");
    private static final Pattern ACTION_SESSION_FIELD =
            Pattern.compile("\"pencilActionSession\"\\s*:\\s*\"([^\"]*)\"");
    private static final Pattern INPUT_CAPS_ARRAY =
            Pattern.compile("\"inputCaps\"\\s*:\\s*\\[([^\\]]*)\\]");

    public enum Phase {
        DOWN("down"),
        MOVE("move"),
        UP("up"),
        CANCEL("cancel"),
        HOVER("hover");

        public final String wireValue;

        Phase(String wireValue) {
            this.wireValue = wireValue;
        }
    }

    public enum Tool {
        PEN("pen"),
        ERASER("eraser");

        public final String wireValue;

        Tool(String wireValue) {
            this.wireValue = wireValue;
        }
    }

    public enum RemoteAction {
        UNDO("undo"),
        REDO("redo"),
        SHORTCUT1("shortcut1"),
        SHORTCUT2("shortcut2");

        public final String wireValue;

        RemoteAction(String wireValue) {
            this.wireValue = wireValue;
        }
    }

    /** Validated immutable stylus sample matching {@code PencilSample} in Swift. */
    public static final class Sample {
        public final Phase phase;
        public final double x;
        public final double y;
        public final double pressure;
        public final double azimuth;
        public final double altitude;
        public final double roll;
        public final Tool tool;

        public Sample(
                Phase phase,
                double x,
                double y,
                double pressure,
                double azimuth,
                double altitude,
                double roll,
                Tool tool) {
            if (phase == null || tool == null
                    || !Double.isFinite(x) || x < 0.0 || x > 1.0
                    || !Double.isFinite(y) || y < 0.0 || y > 1.0
                    || !Double.isFinite(pressure) || pressure < 0.0 || pressure > 1.0
                    || !Double.isFinite(azimuth) || azimuth < -TWO_PI || azimuth > TWO_PI
                    || !Double.isFinite(altitude) || altitude < 0.0 || altitude > HALF_PI
                    || !Double.isFinite(roll) || roll < -TWO_PI || roll > TWO_PI) {
                throw new IllegalArgumentException("stylus sample out of PencilSample bounds");
            }
            this.phase = phase;
            this.x = x;
            this.y = y;
            this.pressure = (phase == Phase.DOWN || phase == Phase.MOVE) ? pressure : 0.0;
            this.azimuth = azimuth;
            this.altitude = altitude;
            this.roll = roll;
            this.tool = tool;
        }

        public static Sample fromAndroidMotion(
                Phase phase,
                double normalizedX,
                double normalizedY,
                double rawPressure,
                double androidTiltRadians,
                double androidOrientationRadians,
                double rollRadians,
                int toolType,
                int buttonState) {
            if (phase == null || !Double.isFinite(normalizedX) || !Double.isFinite(normalizedY)) {
                return null;
            }
            double x = clamp(normalizedX, 0.0, 1.0);
            double y = clamp(normalizedY, 0.0, 1.0);
            double pressure = (phase == Phase.DOWN || phase == Phase.MOVE)
                    ? clampFinite(rawPressure, 0.0, 1.0, 0.5)
                    : 0.0;
            double tilt = clampFinite(androidTiltRadians, 0.0, HALF_PI, 0.0);
            double altitude = clamp(HALF_PI - tilt, 0.0, HALF_PI);
            // Android stylus orientation: 0 rad points up (-Y), +pi/2 points right (+X), pi points down (+Y).
            // DisplayWeave/UIKit azimuth: 0 rad points right (+X), +pi/2 points down (+Y).
            double azimuth = 0.0;
            if (tilt > 1e-6 && Double.isFinite(androidOrientationRadians)) {
                azimuth = clamp(normalizeRadians(androidOrientationRadians - HALF_PI), -TWO_PI, TWO_PI);
            }
            double roll = Double.isFinite(rollRadians)
                    ? clamp(normalizeRadians(rollRadians), -TWO_PI, TWO_PI)
                    : 0.0;
            Tool tool = (toolType == TOOL_TYPE_ERASER || (buttonState & BUTTON_STYLUS_SECONDARY) != 0)
                    ? Tool.ERASER
                    : Tool.PEN;
            return new Sample(phase, x, y, pressure, azimuth, altitude, roll, tool);
        }

        public Sample cancelled() {
            return new Sample(Phase.CANCEL, x, y, 0.0, azimuth, altitude, roll, tool);
        }

        public String toPencilV1Json() {
            return "{\"type\":\"pencil\",\"phase\":\"" + phase.wireValue + "\""
                    + ",\"x\":" + compactNumber(x)
                    + ",\"y\":" + compactNumber(y)
                    + ",\"pressure\":" + compactNumber(pressure)
                    + ",\"azimuth\":" + compactNumber(azimuth)
                    + ",\"altitude\":" + compactNumber(altitude)
                    + "}";
        }

        public String toPencilV2Json() {
            return "{\"type\":\"pencil2\",\"phase\":\"" + phase.wireValue + "\""
                    + ",\"x\":" + compactNumber(x)
                    + ",\"y\":" + compactNumber(y)
                    + ",\"pressure\":" + compactNumber(pressure)
                    + ",\"azimuth\":" + compactNumber(azimuth)
                    + ",\"altitude\":" + compactNumber(altitude)
                    + ",\"roll\":" + compactNumber(roll)
                    + ",\"tool\":\"" + tool.wireValue + "\""
                    + "}";
        }

        public String toTouchFallbackJson() {
            String touchPhase;
            switch (phase) {
                case DOWN:
                    touchPhase = "began";
                    break;
                case MOVE:
                case HOVER:
                    touchPhase = "moved";
                    break;
                case UP:
                    touchPhase = "ended";
                    break;
                case CANCEL:
                default:
                    touchPhase = "cancelled";
                    break;
            }
            return "{\"type\":\"touch\",\"phase\":\"" + touchPhase + "\""
                    + ",\"x\":" + compactNumber(x)
                    + ",\"y\":" + compactNumber(y)
                    + "}";
        }
    }

    private boolean negotiatedV1;
    private boolean negotiatedV2;
    private String actionSession;
    private long actionSequence;
    private Boolean nativeStroke;
    private boolean extendedStroke;
    private boolean hoverActive;
    private Sample lastSample;

    public static boolean isStylusToolType(int toolType) {
        return toolType == TOOL_TYPE_STYLUS || toolType == TOOL_TYPE_ERASER;
    }

    public static String[] advertisedCapabilities(boolean tlsEncrypted) {
        return tlsEncrypted
                ? new String[] {CAPABILITY_V1, CAPABILITY_V2}
                : new String[] {CAPABILITY_V1};
    }

    public synchronized void reset() {
        negotiatedV1 = false;
        negotiatedV2 = false;
        actionSession = null;
        actionSequence = 0L;
        nativeStroke = null;
        extendedStroke = false;
        hoverActive = false;
        lastSample = null;
    }

    /**
     * Updates stylus negotiation from a sender {@code inputConfig} control message.
     * Ignores desktop-only {@code inputConfig} updates so separate DesktopInput grants
     * never clobber an active stylus capability grant.
     */
    public synchronized void configureFromInputConfig(boolean tlsEncrypted, String json) {
        if (json == null || !json.contains("\"inputConfig\"")) {
            return;
        }
        boolean hasPencilStatus = json.contains("\"pencilActionStatus\"");
        boolean mentionsPencilCap = json.contains("\"" + CAPABILITY_V1 + "\"")
                || json.contains("\"" + CAPABILITY_V2 + "\"");
        boolean isDesktopOnlyUpdate = json.contains("\"inputStatus\"")
                && !hasPencilStatus
                && !mentionsPencilCap;
        if (isDesktopOnlyUpdate) {
            return;
        }

        Matcher capsMatcher = INPUT_CAPS_ARRAY.matcher(json);
        String capsBody = capsMatcher.find() ? capsMatcher.group(1) : "";
        boolean hasV1 = capsBody.contains("\"" + CAPABILITY_V1 + "\"");
        boolean hasV2 = capsBody.contains("\"" + CAPABILITY_V2 + "\"");

        negotiatedV1 = hasV1;
        negotiatedV2 = tlsEncrypted && hasV1 && hasV2;

        String status = extractString(ACTION_STATUS_FIELD, json);
        String session = extractString(ACTION_SESSION_FIELD, json);
        if (negotiatedV2
                && "ready".equals(status)
                && session != null
                && UUID_PATTERN.matcher(session).matches()) {
            if (!session.equals(actionSession)) {
                actionSession = session;
                actionSequence = 0L;
            }
        } else {
            actionSession = null;
            actionSequence = 0L;
        }
    }

    public synchronized boolean isNegotiatedV1() {
        return negotiatedV1;
    }

    public synchronized boolean isNegotiatedV2() {
        return negotiatedV2;
    }

    public synchronized boolean isShortcutsAvailable() {
        return negotiatedV2 && actionSession != null;
    }

    /**
     * Translates an Android stylus touch or hover {@code MotionEvent} into zero or more
     * JSON control messages ({@code pencil}, {@code pencil2}, {@code proximity}, or {@code touch}).
     */
    public synchronized List<String> onMotionEvent(
            int actionMasked,
            int toolType,
            double xPx,
            double yPx,
            double viewWidth,
            double viewHeight,
            double pressure,
            double tiltRadians,
            double orientationRadians,
            double rollRadians,
            int buttonState) {
        if (!isStylusToolType(toolType) || viewWidth <= 0.0 || viewHeight <= 0.0) {
            return Collections.emptyList();
        }
        double normX = xPx / viewWidth;
        double normY = yPx / viewHeight;
        boolean insideViewport = Double.isFinite(normX) && Double.isFinite(normY)
                && normX >= 0.0 && normX <= 1.0 && normY >= 0.0 && normY <= 1.0;

        switch (actionMasked) {
            case ACTION_DOWN: {
                hoverActive = false;
                Sample sample = Sample.fromAndroidMotion(
                        Phase.DOWN, normX, normY, pressure,
                        tiltRadians, orientationRadians, rollRadians, toolType, buttonState);
                return sample == null ? Collections.emptyList() : forwardSample(sample);
            }
            case ACTION_MOVE: {
                Sample sample = Sample.fromAndroidMotion(
                        Phase.MOVE, normX, normY, pressure,
                        tiltRadians, orientationRadians, rollRadians, toolType, buttonState);
                return sample == null ? Collections.emptyList() : forwardSample(sample);
            }
            case ACTION_UP: {
                Sample sample = Sample.fromAndroidMotion(
                        Phase.UP, normX, normY, 0.0,
                        tiltRadians, orientationRadians, rollRadians, toolType, buttonState);
                return sample == null ? Collections.emptyList() : forwardSample(sample);
            }
            case ACTION_CANCEL: {
                hoverActive = false;
                Sample sample = Sample.fromAndroidMotion(
                        Phase.CANCEL, normX, normY, 0.0,
                        tiltRadians, orientationRadians, rollRadians, toolType, buttonState);
                return sample == null ? cancelActiveInput() : forwardSample(sample);
            }
            case ACTION_HOVER_ENTER:
            case ACTION_HOVER_MOVE: {
                if (nativeStroke != null || !negotiatedV1) {
                    return Collections.emptyList();
                }
                if (!insideViewport) {
                    return endHoverProximityIfActive();
                }
                hoverActive = true;
                Sample sample = Sample.fromAndroidMotion(
                        Phase.HOVER, normX, normY, 0.0,
                        tiltRadians, orientationRadians, rollRadians, toolType, buttonState);
                return sample == null ? Collections.emptyList() : forwardSample(sample);
            }
            case ACTION_HOVER_EXIT: {
                if (nativeStroke != null) {
                    return Collections.emptyList();
                }
                return endHoverProximityIfActive();
            }
            default:
                return Collections.emptyList();
        }
    }

    /** Cancels any in-flight stylus contact or hover proximity (e.g. on pause/resize). */
    public synchronized List<String> cancelActiveInput() {
        List<String> out = new ArrayList<>(2);
        if (nativeStroke != null && lastSample != null) {
            Sample cancelled = lastSample.cancelled();
            out.add(encodeSample(cancelled, nativeStroke, extendedStroke));
            nativeStroke = null;
            extendedStroke = false;
            lastSample = cancelled;
        }
        out.addAll(endHoverProximityIfActive());
        return out;
    }

    /** Emits a {@code pencilAction} JSON message when shortcuts are negotiated over TLS. */
    public synchronized String nextPencilActionJson(RemoteAction action) {
        if (action == null || !negotiatedV2 || actionSession == null
                || actionSequence >= MAX_SAFE_SEQUENCE) {
            return null;
        }
        long seq = ++actionSequence;
        return pencilActionJson(actionSession, seq, action);
    }

    public static String pencilActionJson(String inputSession, long sequence, RemoteAction action) {
        if (inputSession == null || !UUID_PATTERN.matcher(inputSession).matches()
                || sequence < 1L || sequence > MAX_SAFE_SEQUENCE || action == null) {
            throw new IllegalArgumentException("invalid pencilAction arguments");
        }
        return "{\"type\":\"pencilAction\",\"inputSession\":\"" + inputSession + "\""
                + ",\"sequence\":" + sequence
                + ",\"action\":\"" + action.wireValue + "\"}";
    }

    public static String proximityJson(boolean entering, double x, double y) {
        double cx = clampFinite(x, 0.0, 1.0, 0.5);
        double cy = clampFinite(y, 0.0, 1.0, 0.5);
        return "{\"type\":\"proximity\",\"entering\":" + entering
                + ",\"x\":" + compactNumber(cx)
                + ",\"y\":" + compactNumber(cy)
                + "}";
    }

    public synchronized List<String> forwardSample(Sample sample) {
        if (sample == null) {
            return Collections.emptyList();
        }
        List<String> messages = new ArrayList<>(2);
        switch (sample.phase) {
            case DOWN:
                if (nativeStroke != null && lastSample != null) {
                    Sample cancelled = lastSample.cancelled();
                    messages.add(encodeSample(cancelled, nativeStroke, extendedStroke));
                }
                nativeStroke = negotiatedV1;
                extendedStroke = negotiatedV1 && negotiatedV2;
                break;
            case MOVE:
            case UP:
            case CANCEL:
                if (nativeStroke == null) {
                    return Collections.emptyList();
                }
                break;
            case HOVER:
                if (nativeStroke != null || !negotiatedV1) {
                    return Collections.emptyList();
                }
                break;
        }
        boolean useNative = nativeStroke != null ? nativeStroke : negotiatedV1;
        boolean useExtended = nativeStroke != null ? extendedStroke : (negotiatedV1 && negotiatedV2);
        messages.add(encodeSample(sample, useNative, useExtended));
        lastSample = sample;
        if (sample.phase == Phase.UP || sample.phase == Phase.CANCEL) {
            nativeStroke = null;
            extendedStroke = false;
        }
        return messages;
    }

    private List<String> endHoverProximityIfActive() {
        if (!hoverActive) {
            return Collections.emptyList();
        }
        hoverActive = false;
        if (!negotiatedV1) {
            return Collections.emptyList();
        }
        double x = lastSample != null ? lastSample.x : 0.5;
        double y = lastSample != null ? lastSample.y : 0.5;
        return Collections.singletonList(proximityJson(false, x, y));
    }

    private static String encodeSample(Sample sample, boolean nativeEnabled, boolean extendedEnabled) {
        if (!nativeEnabled) {
            return sample.toTouchFallbackJson();
        }
        return extendedEnabled ? sample.toPencilV2Json() : sample.toPencilV1Json();
    }

    private static String extractString(Pattern pattern, String json) {
        Matcher matcher = pattern.matcher(json);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static double normalizeRadians(double rad) {
        double wrapped = rad % TWO_PI;
        if (wrapped > Math.PI) {
            wrapped -= TWO_PI;
        } else if (wrapped < -Math.PI) {
            wrapped += TWO_PI;
        }
        return wrapped;
    }

    private static double clamp(double value, double min, double max) {
        return Math.max(min, Math.min(max, value));
    }

    private static double clampFinite(double value, double min, double max, double fallback) {
        return Double.isFinite(value) ? clamp(value, min, max) : fallback;
    }

    static String compactNumber(double value) {
        if (!Double.isFinite(value)) {
            throw new IllegalArgumentException("non-finite JSON number");
        }
        if (Math.abs(value) < 1e-9) {
            return "0";
        }
        long rounded = Math.round(value);
        if (Math.abs(value - rounded) < 1e-9) {
            return Long.toString(rounded);
        }
        String formatted = String.format(Locale.US, "%.6f", value);
        int end = formatted.length();
        while (end > 0 && formatted.charAt(end - 1) == '0') {
            end--;
        }
        if (end > 0 && formatted.charAt(end - 1) == '.') {
            end--;
        }
        String trimmed = formatted.substring(0, end);
        return "-0".equals(trimmed) ? "0" : trimmed;
    }
}
