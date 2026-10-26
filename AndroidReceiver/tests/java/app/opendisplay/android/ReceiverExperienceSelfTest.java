package app.opendisplay.android;

public final class ReceiverExperienceSelfTest {
    private static void require(boolean ok, String message) {
        if (!ok) throw new AssertionError(message);
    }
    public static void main(String[] args) throws Exception {
        VideoViewport portrait = VideoViewport.fit(1080, 2340, 640, 360);
        require(portrait.width == 1080 && portrait.height == 608, "landscape video must not stretch to a portrait panel");
        require(!portrait.contains(540, 200) && portrait.contains(540, 1170), "letterbox rejects input");
        require(!portrait.contains(Double.NaN, 1170), "invalid coordinates rejected");
        VideoViewport rotated = VideoViewport.fit(2340, 1080, 640, 360);
        require(rotated.width == 1920 && rotated.height == 1080 && rotated.left == 210, "landscape resize preserves ratio");
        VideoViewport tablet = VideoViewport.fit(2560, 1600, 1024, 768);
        require(tablet.width == 2133 && tablet.height == 1600, "4:3 into 16:10 remains aspect-correct");
        require(VideoViewport.fit(0, 1600, 640, 360).width == 0, "unlaid-out view has no touch area");
        require(CursorImagePolicy.accepts(1024, 32, 32, 0, 0, .02, .03), "normal cursor accepted");
        require(!CursorImagePolicy.accepts(1024, 8192, 8192, 0, 0, .02, .03), "expanded PNG size rejected before allocation");
        require(!CursorImagePolicy.accepts(600000, 32, 32, 0, 0, .02, .03), "compressed size bound");
        require(!CursorImagePolicy.accepts(1024, 32, 32, 0, Double.NaN, .02, .03), "invalid anchor rejected");
        require(!CursorImagePolicy.accepts(1024, 32, 32, 0, 0, 2, .03), "cursor cannot cover more than the video");
        require(!FrameQueuePolicy.expired(100, 100 + 149_000_000), "short scheduling bursts remain admissible");
        require(FrameQueuePolicy.expired(100, 100 + 150_000_000), "both FIFOs share one 150 ms age budget");
        ReferenceChainRecovery chain = new ReferenceChainRecovery();
        require(chain.breakChain(1), "expired predictive frame starts recovery");
        require(chain.shouldReject(false, 2), "dependent frame cannot bypass expired reference");
        require(!chain.shouldReject(true, 3), "fresh keyframe restores decoding");
        byte[] idr = new byte[] {0, 0, 0, 1, 0x65, 1, 2, 3};
        try (VideoFramePacket original = VideoFramePacket.parse(idr, 0, VideoStreamConfig.DEFAULT)) {
            Thread.sleep(100);
            try (VideoFramePacket retained = original.retained()) {
                Thread.sleep(60);
                require(retained.queueDeadlineExpired(), "moving to the second FIFO must not refresh a frame's deadline");
            }
        }
        TouchGestureCoordinator touch = new TouchGestureCoordinator(.01);
        require(touch.begin(.5, .5).isEmpty(), "wait briefly to disambiguate two fingers");
        require(touch.commitHold().get(0).phase.equals("began"), "stationary hold presses before release");
        require(touch.commitHold().isEmpty(), "timer cannot double-press");
        require(touch.end(.5, .5).get(0).phase.equals("ended"), "held button releases");
        touch.begin(.2, .3);
        touch.cancel();
        require(touch.commitHold().isEmpty(), "scroll or disconnect cancels pending hold");
        touch.begin(.2, .3); touch.commitHold();
        require(touch.cancel().get(0).phase.equals("cancelled"), "active hold cancellation releases Mac input");
        require(touch.end(.2, .3).isEmpty(), "finger lifting after scroll cannot tap");
        TouchGestureCoordinator wide = new TouchGestureCoordinator(10, 1000, 500);
        wide.begin(.5, .5);
        require(wide.move(.505, .5).isEmpty(), "five horizontal pixels stay below movement slop");
        require(wide.move(.511, .5).size() == 2, "eleven horizontal pixels start a drag");
        wide.cancel(); wide.begin(.5, .5);
        require(wide.move(.5, .51).isEmpty(), "five vertical pixels use the same movement slop");
        require(wide.move(.5, .522).size() == 2, "eleven vertical pixels start a drag");
        System.out.println("Receiver experience: aspect fit, letterbox, cursor bounds and stationary holds PASS");
    }
}
