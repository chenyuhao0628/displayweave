package app.opendisplay.android;

public final class ExperimentalFpsPolicySelfTest {
    public static void main(String[] args) {
        check(!ExperimentalFpsPolicy.allowsNative60(false, 2400, 1080, 60));
        check(ExperimentalFpsPolicy.allowsNative60(true, 2400, 1080, 60));
        check(ExperimentalFpsPolicy.allowsNative60(true, 1080, 2400, 60));
        check(!ExperimentalFpsPolicy.allowsNative60(true, 2400, 1080, 90));
        check(!ExperimentalFpsPolicy.allowsNative60(true, 2560, 1440, 60));
        check(!ExperimentalFpsPolicy.allowsNative60(true, 0, 1080, 60));
        check(!ExperimentalFpsPolicy.allowsNative60(true, 2400, 1080, 0));
        System.out.println("ExperimentalFpsPolicySelfTest PASS");
    }
    private static void check(boolean value) {
        if (!value) throw new AssertionError("Experimental FPS envelope regression");
    }
}
