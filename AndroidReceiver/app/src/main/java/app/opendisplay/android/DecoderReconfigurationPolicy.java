package app.opendisplay.android;

final class DecoderReconfigurationPolicy {
    private DecoderReconfigurationPolicy() {
    }

    static boolean requiresReplacement(VideoStreamConfig current, VideoStreamConfig next) {
        if (current == null || next == null) {
            return true;
        }
        return !current.codec.equals(next.codec)
                || current.fps != next.fps
                || current.width != next.width
                || current.height != next.height;
    }
}
