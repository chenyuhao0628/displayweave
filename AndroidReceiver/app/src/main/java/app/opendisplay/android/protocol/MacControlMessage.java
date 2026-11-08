package app.opendisplay.android.protocol;

import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class MacControlMessage {
    public final String type;
    public final double x;
    public final double y;
    public final boolean visible;
    public final double normalizedWidth;
    public final double normalizedHeight;
    public final double anchorX;
    public final double anchorY;
    public final String pngBase64;

    private MacControlMessage(String type, double x, double y, boolean visible,
                              double normalizedWidth, double normalizedHeight,
                              double anchorX, double anchorY, String pngBase64) {
        this.type = type;
        this.x = x;
        this.y = y;
        this.visible = visible;
        this.normalizedWidth = normalizedWidth;
        this.normalizedHeight = normalizedHeight;
        this.anchorX = anchorX;
        this.anchorY = anchorY;
        this.pngBase64 = pngBase64;
    }

    private static final Pattern TYPE_PATTERN = stringPattern("type");
    private static final Pattern X_PATTERN = numberPattern("x");
    private static final Pattern Y_PATTERN = numberPattern("y");
    private static final Pattern V_PATTERN = numberPattern("v");
    private static final Pattern NW_PATTERN = numberPattern("nw");
    private static final Pattern NH_PATTERN = numberPattern("nh");
    private static final Pattern AX_PATTERN = numberPattern("ax");
    private static final Pattern AY_PATTERN = numberPattern("ay");
    private static final Pattern PNG_PATTERN = stringPattern("png");

    public static MacControlMessage parse(String json) {
        return new MacControlMessage(
                stringField(json, TYPE_PATTERN, ""),
                numberField(json, X_PATTERN, 0),
                numberField(json, Y_PATTERN, 0),
                numberField(json, V_PATTERN, 0) == 1,
                numberField(json, NW_PATTERN, 0),
                numberField(json, NH_PATTERN, 0),
                numberField(json, AX_PATTERN, 0),
                numberField(json, AY_PATTERN, 0),
                stringField(json, PNG_PATTERN, ""));
    }

    private static Pattern numberPattern(String key) {
        return Pattern.compile("\"" + Pattern.quote(key)
                + "\"\\s*:\\s*(-?[0-9]+(?:\\.[0-9]+)?)");
    }

    private static Pattern stringPattern(String key) {
        return Pattern.compile("\"" + Pattern.quote(key) + "\"\\s*:\\s*\"([^\"]*)\"");
    }

    private static double numberField(String json, Pattern pattern, double fallback) {
        Matcher matcher = pattern.matcher(json);
        return matcher.find() ? Double.parseDouble(matcher.group(1)) : fallback;
    }

    private static String stringField(String json, Pattern pattern, String fallback) {
        Matcher matcher = pattern.matcher(json);
        return matcher.find() ? matcher.group(1) : fallback;
    }
}
