package app.opendisplay.android;

/** One pixel rectangle shared by video, cursor and touch surfaces. */
public final class VideoViewport {
    public final int left, top, width, height;

    private VideoViewport(int left, int top, int width, int height) {
        this.left = left; this.top = top; this.width = width; this.height = height;
    }

    public static VideoViewport fit(int hostWidth, int hostHeight, int videoWidth, int videoHeight) {
        if (hostWidth <= 0 || hostHeight <= 0) return new VideoViewport(0, 0, 0, 0);
        if (videoWidth <= 0 || videoHeight <= 0) return new VideoViewport(0, 0, hostWidth, hostHeight);
        double scale = Math.min((double) hostWidth / videoWidth, (double) hostHeight / videoHeight);
        int width = Math.max(1, Math.min(hostWidth, (int) Math.round(videoWidth * scale)));
        int height = Math.max(1, Math.min(hostHeight, (int) Math.round(videoHeight * scale)));
        return new VideoViewport((hostWidth - width) / 2, (hostHeight - height) / 2, width, height);
    }

    public boolean contains(double x, double y) {
        return Double.isFinite(x) && Double.isFinite(y) && width > 0 && height > 0
                && x >= left && x < left + width && y >= top && y < top + height;
    }
}
