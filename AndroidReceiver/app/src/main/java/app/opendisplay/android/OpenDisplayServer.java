package app.opendisplay.android;

import android.content.Context;
import android.util.Base64;
import android.view.Surface;

import org.json.JSONObject;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;

import app.opendisplay.android.protocol.LengthPrefixedProtocol;
import app.opendisplay.android.protocol.MacControlMessage;

public final class OpenDisplayServer implements H264SurfaceDecoder.Listener, NsdAdvertiser.Listener {
    private static final int PORT = 9000;

    private final Listener listener;
    private final ExecutorService decoderWorker = Executors.newSingleThreadExecutor();
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
    private final String installId;
    private final NsdAdvertiser advertiser;
    private final ReceiverTransport transport;
    private final ReceiverConnectionCoordinator connectionCoordinator;
    private volatile boolean wifiAdvertisingEnabled;
    private volatile int listeningPort;
    private volatile DisplaySpec displaySpec;
    private volatile boolean running;
    private H264SurfaceDecoder decoder;
    private Double clockOffsetMs;
    private final ClockOffsetEstimator clockEstimator = new ClockOffsetEstimator(8);
    private int renderedFrames;
    private int decodedFrames;
    private int receivedFrames;
    private int droppedFramesAndroid;
    private int queueDepthAndroid;
    private long latestFrameAgeMsSum;
    private int latestFrameAgeSamples;
    private MetricDistribution frameAgeDistribution = new MetricDistribution(240);
    private long endToEndLatencyMsSum;
    private int endToEndLatencySamples;
    private long decodeLatencyMsSum;
    private int decodeLatencySamples;
    private long metricsWindowStartMs;
    private double lastRttMs;
    private double lastInputP50Ms;
    private double lastInputP95Ms;
    private int lastMacRequestedFps = 60;
    private int lastMacCaptureFps;
    private int lastMacActualVirtualDisplayRefreshRate = 60;
    private int lastMacEncodedFps;
    private int lastMacSentFps;
    private int lastMacAverageFrameSize;
    private int lastMacEncodeLatencyMs;
    private int lastMacQueueDepth;
    private int lastMacDroppedFrames;
    private String lastMacTransport = "wifi";
    private VideoStreamConfig currentStreamConfig = VideoStreamConfig.DEFAULT;
    private byte[] latestVideoFrame;
    private VideoFrameTelemetry latestVideoFrameTelemetry;
    private final DecodeWorkerState decodeWorkerState = new DecodeWorkerState();

    public interface Listener {
        void onStatus(String status);
        void onConnected(boolean connected);
        void onStreaming(boolean streaming);
        void onCursor(double x, double y, boolean visible);
        void onCursorImage(byte[] png, double anchorX, double anchorY,
                           double normalizedWidth, double normalizedHeight);
        void onStreamConfig(VideoStreamConfig config);
        float currentDisplayRefreshRate();
        void onMetrics(StreamMetrics metrics);
    }

    public OpenDisplayServer(Context context, DisplaySpec displaySpec, Listener listener) {
        this(context, displaySpec, listener, new WifiTcpReceiverTransport(PORT), true);
    }

    public OpenDisplayServer(Context context, DisplaySpec displaySpec, Listener listener,
                             boolean wifiAdvertisingEnabled) {
        this(context, displaySpec, listener, new WifiTcpReceiverTransport(PORT),
                wifiAdvertisingEnabled);
    }

    OpenDisplayServer(Context context, DisplaySpec displaySpec, Listener listener,
                      ReceiverTransport transport) {
        this(context, displaySpec, listener, transport, true);
    }

    OpenDisplayServer(Context context, DisplaySpec displaySpec, Listener listener,
                      ReceiverTransport transport, boolean wifiAdvertisingEnabled) {
        this.displaySpec = displaySpec;
        this.listener = listener;
        this.transport = transport;
        this.installId = InstallId.get(context);
        this.advertiser = new NsdAdvertiser(context, this);
        this.wifiAdvertisingEnabled = wifiAdvertisingEnabled;
        this.connectionCoordinator = new ReceiverConnectionCoordinator(
                new ReceiverConnectionCoordinator.Actions() {
                    @Override
                    public void resetQueuedFrames() {
                        OpenDisplayServer.this.resetQueuedFrames();
                    }

                    @Override
                    public void releaseDecoder() {
                        H264SurfaceDecoder activeDecoder = decoder;
                        if (activeDecoder != null) {
                            activeDecoder.release();
                        }
                    }

                    @Override
                    public void setConnected(boolean connected) {
                        listener.onConnected(connected);
                    }

                    @Override
                    public void stopStreaming() {
                        listener.onStreaming(false);
                    }
                });
    }

    public void start(Surface surface) {
        if (running) {
            return;
        }
        running = true;
        decoder = new H264SurfaceDecoder(surface, this);
        metricsWindowStartMs = System.currentTimeMillis();
        transport.start(new ReceiverTransport.Listener() {
            @Override
            public void onListening(int port) {
                listeningPort = port;
                if (wifiAdvertisingEnabled) {
                    startWifiAdvertising(port);
                }
                listener.onStatus("正在监听 :" + port + " / " + transport.name());
            }

            @Override
            public void onConnected(String peer) {
                connectionCoordinator.onConnected();
                listener.onStatus("Mac 已连接：" + peer);
                sendHello();
            }

            @Override
            public void onPayload(byte[] payload) {
                handleTransportPayload(payload);
            }

            @Override
            public void onDisconnected() {
                connectionCoordinator.onDisconnected();
            }

            @Override
            public void onError(String message) {
                listener.onStatus(message);
            }
        });
        timer.scheduleAtFixedRate(this::sendPingIfConnected, 2, 2, TimeUnit.SECONDS);
        timer.scheduleAtFixedRate(this::publishStatsSafely, 1, 1, TimeUnit.SECONDS);
    }

    public void stop() {
        running = false;
        listeningPort = 0;
        advertiser.stop();
        transport.stop();
        resetQueuedFrames();
        if (decoder != null) {
            decoder.release();
        }
        decoderWorker.shutdownNow();
        timer.shutdownNow();
    }

    public void updateDisplay(DisplaySpec spec) {
        displaySpec = spec;
        sendHello();
    }

    public synchronized void enableWifiAdvertising() {
        if (wifiAdvertisingEnabled) {
            return;
        }
        wifiAdvertisingEnabled = true;
        if (running && listeningPort > 0) {
            startWifiAdvertising(listeningPort);
        }
    }

    private void startWifiAdvertising(int port) {
        try {
            advertiser.start("DisplayWeave Android", installId, port);
        } catch (SecurityException error) {
            listener.onStatus("WiFi 广播等待附近设备权限；USB 仍可使用");
        }
    }

    public void sendTouch(String phase, double x, double y) {
        Double macTime = clockOffsetMs == null ? null : LengthPrefixedProtocol.nowMs() + clockOffsetMs;
        sendJson(LengthPrefixedProtocol.touchJson(phase, x, y, macTime));
    }

    public void sendScroll(double dx, double dy) {
        sendJson(LengthPrefixedProtocol.scrollJson(dx, dy));
    }

    private void enqueueVideoFrame(byte[] payload) {
        VideoFrameTelemetry telemetry = VideoFrameTelemetry.fromWirePayload(
                payload, System.currentTimeMillis());
        synchronized (this) {
            receivedFrames++;
            if (latestVideoFrame != null) {
                boolean queuedImportant = VideoFrameClassifier.isImportant(
                        latestVideoFrame, currentStreamConfig);
                boolean incomingImportant = VideoFrameClassifier.isImportant(
                        payload, currentStreamConfig);
                if (queuedImportant && !incomingImportant) {
                    droppedFramesAndroid++;
                    return;
                }
                droppedFramesAndroid++;
            }
            latestVideoFrame = payload;
            latestVideoFrameTelemetry = telemetry;
            queueDepthAndroid = 1;
            if (decodeWorkerState.markFrameAvailable()) {
                decoderWorker.execute(this::drainLatestVideoFrames);
            }
        }
    }

    private void drainLatestVideoFrames() {
        while (running) {
            byte[] frame;
            VideoFrameTelemetry telemetry;
            synchronized (this) {
                frame = latestVideoFrame;
                telemetry = latestVideoFrameTelemetry;
                latestVideoFrame = null;
                latestVideoFrameTelemetry = null;
                queueDepthAndroid = 0;
                if (frame == null) {
                    decodeWorkerState.markIdle();
                    return;
                }
            }
            H264SurfaceDecoder activeDecoder = decoder;
            if (activeDecoder != null) {
                activeDecoder.queueFrame(frame, telemetry);
            }
        }
        synchronized (this) {
            decodeWorkerState.markIdle();
        }
    }

    private void handleTransportPayload(byte[] payload) {
        if (LengthPrefixedProtocol.isPureJsonControl(payload)) {
            handleMacJson(new String(payload, StandardCharsets.UTF_8));
        } else if (decoder != null) {
            enqueueVideoFrame(payload);
        }
    }

    private void handleMacJson(String json) {
        try {
            JSONObject object = new JSONObject(json);
            String type = object.optString("type", "");
            if ("ping".equals(type)) {
                double t = object.optDouble("t", 0);
                MacPingMetrics macMetrics = MacPingMetrics.parse(
                        json, lastInputP50Ms, lastInputP95Ms, lastMacRequestedFps);
                lastInputP50Ms = macMetrics.inputP50Ms;
                lastInputP95Ms = macMetrics.inputP95Ms;
                lastMacRequestedFps = macMetrics.requestedFps;
                lastMacCaptureFps = object.optInt("capFps", lastMacCaptureFps);
                lastMacActualVirtualDisplayRefreshRate = object.optInt(
                        "actualVirtualDisplayRefreshRate",
                        lastMacActualVirtualDisplayRefreshRate);
                lastMacEncodedFps = object.optInt("encodedFps", lastMacEncodedFps);
                lastMacSentFps = object.optInt("sentFps", lastMacSentFps);
                lastMacAverageFrameSize = object.optInt("averageFrameSize", lastMacAverageFrameSize);
                lastMacEncodeLatencyMs = (int) Math.round(object.optDouble(
                        "encodeLatencyMs", lastMacEncodeLatencyMs));
                lastMacQueueDepth = object.has("queueDepthMac")
                        ? object.optInt("queueDepthMac", lastMacQueueDepth)
                        : object.optInt("pending", lastMacQueueDepth);
                lastMacDroppedFrames = object.has("droppedFramesMac")
                        ? object.optInt("droppedFramesMac", lastMacDroppedFrames)
                        : object.optInt("drops", lastMacDroppedFrames);
                sendJson(LengthPrefixedProtocol.pongJson(t, LengthPrefixedProtocol.nowMs()));
            } else if ("pong".equals(type)) {
                double t1 = object.optDouble("t", 0);
                double mt = object.optDouble("mt", 0);
                double t2 = LengthPrefixedProtocol.nowMs();
                double rtt = t2 - t1;
                if (rtt >= 0 && rtt < 2000) {
                    clockOffsetMs = mt - (t1 + t2) / 2.0;
                    lastRttMs = rtt;
                }
                if (object.has("mr") && object.has("ms")) {
                    clockEstimator.addSample(
                            t1, object.optDouble("mr"), object.optDouble("ms"), t2);
                    if (clockEstimator.state() == ClockOffsetEstimator.State.STABLE) {
                        clockOffsetMs = (double) clockEstimator.offsetMs();
                    }
                }
            } else if ("cursor".equals(type)) {
                MacControlMessage cursor = MacControlMessage.parse(json);
                listener.onCursor(cursor.x, cursor.y, cursor.visible);
            } else if ("cursorImg".equals(type)) {
                MacControlMessage cursor = MacControlMessage.parse(json);
                byte[] png = Base64.decode(cursor.pngBase64, Base64.DEFAULT);
                listener.onCursorImage(png, cursor.anchorX, cursor.anchorY,
                        cursor.normalizedWidth, cursor.normalizedHeight);
            } else if ("streamConfig".equals(type)) {
                if (decoder != null) {
                    VideoStreamConfig config = VideoStreamConfig.from(
                            object.optString("codec", "h264"),
                            object.optInt("fps", 60),
                            object.optInt("width", displaySpec.pixelsWide),
                            object.optInt("height", displaySpec.pixelsHigh),
                            object.optInt("bitrate", 0));
                    currentStreamConfig = config;
                    lastMacTransport = object.optString("transport", lastMacTransport);
                    listener.onStreamConfig(config);
                    decoder.applyStreamConfig(
                            config.codec,
                            config.fps,
                            config.width,
                            config.height);
                }
            }
        } catch (Exception ignored) {
        }
    }

    private void sendHello() {
        DisplaySpec spec = displaySpec;
        if (spec == null) {
            return;
        }
        sendJson(LengthPrefixedProtocol.helloJson(
                spec.pixelsWide,
                spec.pixelsHigh,
                spec.scale,
                spec.refreshRate,
                spec.maxFps,
                spec.supportedCodecs,
                spec.preferredCodec,
                spec.deviceModel,
                spec.androidSdk,
                spec.transport,
                "Android",
                installId));
    }

    private void sendPingIfConnected() {
        sendJson(LengthPrefixedProtocol.pingJson(LengthPrefixedProtocol.nowMs()));
    }

    private void sendJson(String json) {
        transport.send(json.getBytes(StandardCharsets.UTF_8));
    }

    private synchronized void resetQueuedFrames() {
        latestVideoFrame = null;
        latestVideoFrameTelemetry = null;
        queueDepthAndroid = 0;
        decodeWorkerState.markQueueReset();
    }

    @Override
    public void onDecoderStatus(String status) {
        listener.onStatus(status);
        if (status.startsWith("正在接收")) {
            listener.onStreaming(true);
        }
    }

    @Override
    public void onDecoderNeedsKeyframe() {
        sendJson(LengthPrefixedProtocol.keyframeRequestJson());
    }

    @Override
    public void onDecoderCodecFailure(String codec, String message) {
        String fallbackStatus = CodecFallbackStatus.messageForCodecFailure(codec);
        if (fallbackStatus != null) {
            listener.onStatus(fallbackStatus);
        }
        sendJson(LengthPrefixedProtocol.codecFailureJson(codec, message));
    }

    @Override
    public synchronized void onDecoderFrameDropped() {
        droppedFramesAndroid++;
    }

    @Override
    public synchronized void onDecoderFrameDecoded() {
        decodedFrames++;
    }

    @Override
    public synchronized void onDecoderFrameRendered(VideoFrameTelemetry telemetry) {
        renderedFrames++;
        long now = System.currentTimeMillis();
        if (telemetry != null) {
            long frameAgeMs = telemetry.latestFrameAgeMs(now);
            latestFrameAgeMsSum += frameAgeMs;
            latestFrameAgeSamples++;
            frameAgeDistribution.add(frameAgeMs);
            Double stableOffset = stableOffsetOrNull(clockEstimator);
            long endToEndLatencyMs = telemetry.endToEndLatencyMs(now, stableOffset);
            if (endToEndLatencyMs >= 0) {
                this.endToEndLatencyMsSum += endToEndLatencyMs;
                endToEndLatencySamples++;
            }
            long decodeLatencyMs = telemetry.decodeLatencyMs(now, stableOffset);
            if (decodeLatencyMs >= 0) {
                this.decodeLatencyMsSum += decodeLatencyMs;
                decodeLatencySamples++;
            }
        }
        publishStatsIfDue(now);
    }

    private void publishStatsIfDue() {
        publishStatsIfDue(System.currentTimeMillis());
    }

    private void publishStatsSafely() {
        try {
            publishStatsIfDue();
        } catch (RuntimeException error) {
            android.util.Log.w("DisplayWeave", "stats publication failed", error);
        }
    }

    private synchronized void publishStatsIfDue(long now) {
        long elapsed = now - metricsWindowStartMs;
        if (shouldPublishStats(elapsed)) {
            int renderedFps = (int) Math.round(renderedFrames * 1000.0 / elapsed);
            int decodedFps = (int) Math.round(decodedFrames * 1000.0 / elapsed);
            int receivedFps = (int) Math.round(receivedFrames * 1000.0 / elapsed);
            int dropped = droppedFramesAndroid;
            int latestFrameAgeMs = averageAndResetLatestFrameAge();
            int endToEndLatencyMs = averageAndResetEndToEndLatency();
            int decodeLatencyMs = averageAndResetDecodeLatency();
            MetricDistribution completedFrameAges = frameAgeDistribution;
            frameAgeDistribution = new MetricDistribution(240);
            renderedFrames = 0;
            decodedFrames = 0;
            receivedFrames = 0;
            droppedFramesAndroid = 0;
            metricsWindowStartMs = now;
            float actualAndroidHz = listener.currentDisplayRefreshRate();
            listener.onMetrics(new StreamMetrics(
                    receivedFps,
                    renderedFps,
                    decodedFps,
                    lastRttMs,
                    lastInputP50Ms,
                    lastMacCaptureFps,
                    currentStreamConfig.fps,
                    currentStreamConfig.codec,
                    currentStreamConfig.bitrate,
                    dropped,
                    queueDepthAndroid,
                    actualAndroidHz,
                    latestFrameAgeMs,
                    endToEndLatencyMs,
                    decodeLatencyMs,
                    lastMacActualVirtualDisplayRefreshRate,
                    lastMacEncodedFps,
                    lastMacSentFps,
                    lastMacAverageFrameSize,
                    lastMacEncodeLatencyMs,
                    lastMacQueueDepth,
                    lastMacDroppedFrames,
                    lastMacTransport));
            boolean stableClock = clockEstimator.state() == ClockOffsetEstimator.State.STABLE;
            DisplaySpec spec = displaySpec;
            ReceiverStatsSnapshot snapshot = new ReceiverStatsSnapshot(
                    now,
                    spec == null ? "" : spec.deviceModel,
                    lastMacTransport,
                    currentStreamConfig.codec,
                    currentStreamConfig.width,
                    currentStreamConfig.height,
                    lastMacRequestedFps,
                    actualAndroidHz,
                    receivedFps,
                    decodedFps,
                    renderedFps,
                    lastRttMs > 0 ? lastRttMs : null,
                    stableClock ? (double) clockEstimator.offsetMs() : null,
                    stableClock ? (double) clockEstimator.confidenceMs() : null,
                    stableClock ? lastRttMs : null,
                    stableClock ? "stable" : "estimating",
                    completedFrameAges.size() == 0 ? null : (double) latestFrameAgeMs,
                    missingAsNull(completedFrameAges.latest()),
                    missingAsNull(completedFrameAges.p50()),
                    missingAsNull(completedFrameAges.p95()),
                    missingAsNull(completedFrameAges.p99()),
                    stableClock && endToEndLatencyMs > 0 ? (double) endToEndLatencyMs : null,
                    stableClock && decodeLatencyMs > 0 ? (double) decodeLatencyMs : null,
                    queueDepthAndroid,
                    dropped,
                    lastInputP50Ms > 0 ? lastInputP50Ms : null,
                    lastInputP95Ms > 0 ? lastInputP95Ms : null);
            sendJson(snapshot.toJson());
        }
    }

    static boolean shouldPublishStats(long elapsedMs) {
        return elapsedMs >= 1000;
    }

    static Double stableOffsetOrNull(ClockOffsetEstimator estimator) {
        return estimator.state() == ClockOffsetEstimator.State.STABLE
                ? (double) estimator.offsetMs()
                : null;
    }

    private static Long missingAsNull(long value) {
        return value == MetricDistribution.MISSING_MS ? null : value;
    }

    static final class MacPingMetrics {
        final double inputP50Ms;
        final double inputP95Ms;
        final int requestedFps;

        MacPingMetrics(double inputP50Ms, double inputP95Ms, int requestedFps) {
            this.inputP50Ms = inputP50Ms;
            this.inputP95Ms = inputP95Ms;
            this.requestedFps = requestedFps;
        }

        static MacPingMetrics parse(String json, double previousP50,
                                    double previousP95, int previousRequestedFps) {
            double p50 = number(json, "inputP50Ms", number(json, "inp50", previousP50));
            double p95 = number(json, "inputP95Ms", number(json, "inp95", previousP95));
            int requestedFps = (int) Math.round(number(
                    json, "requestedFps", previousRequestedFps));
            return new MacPingMetrics(p50, p95, requestedFps);
        }

        private static double number(String json, String field, double fallback) {
            String key = "\"" + field + "\":";
            int start = json.indexOf(key);
            if (start < 0) {
                return fallback;
            }
            start += key.length();
            while (start < json.length() && Character.isWhitespace(json.charAt(start))) {
                start++;
            }
            int end = start;
            while (end < json.length()) {
                char c = json.charAt(end);
                if ((c < '0' || c > '9') && c != '-' && c != '+' && c != '.'
                        && c != 'e' && c != 'E') {
                    break;
                }
                end++;
            }
            try {
                if (end == start) {
                    return fallback;
                }
                double parsed = Double.parseDouble(json.substring(start, end));
                return Double.isFinite(parsed) ? parsed : fallback;
            } catch (NumberFormatException ignored) {
                return fallback;
            }
        }
    }

    private int averageAndResetLatestFrameAge() {
        int average = averageMs(latestFrameAgeMsSum, latestFrameAgeSamples);
        latestFrameAgeMsSum = 0;
        latestFrameAgeSamples = 0;
        return average;
    }

    private int averageAndResetEndToEndLatency() {
        int average = averageMs(endToEndLatencyMsSum, endToEndLatencySamples);
        endToEndLatencyMsSum = 0;
        endToEndLatencySamples = 0;
        return average;
    }

    private int averageAndResetDecodeLatency() {
        int average = averageMs(decodeLatencyMsSum, decodeLatencySamples);
        decodeLatencyMsSum = 0;
        decodeLatencySamples = 0;
        return average;
    }

    private static int averageMs(long sum, int samples) {
        if (samples <= 0) {
            return 0;
        }
        return (int) Math.round(sum / (double) samples);
    }

    @Override
    public void onNsdStatus(String status) {
        listener.onStatus(status);
    }
}
