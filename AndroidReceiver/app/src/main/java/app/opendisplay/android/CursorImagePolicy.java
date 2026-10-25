package app.opendisplay.android;

/** Check compressed size, decoded size and geometry before bitmap allocation. */
public final class CursorImagePolicy {
    public static final int MAX_BYTES = 512 * 1024;
    public static boolean accepts(int bytes, int width, int height,
                                  double anchorX, double anchorY, double normWidth, double normHeight) {
        return bytes > 0 && bytes <= MAX_BYTES && width > 0 && height > 0 && width <= 512 && height <= 512
                && unit(anchorX) && unit(anchorY) && unit(normWidth) && unit(normHeight)
                && normWidth > 0 && normHeight > 0;
    }
    private static boolean unit(double value) {
        return Double.isFinite(value) && value >= 0 && value <= 1;
    }
    private CursorImagePolicy() {}
}
