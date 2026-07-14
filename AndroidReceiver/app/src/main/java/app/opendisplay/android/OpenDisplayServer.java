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

public final class OpenDisplayServer implements NsdAdvertiser.Listener {
    private static final int PORT = 9000;

    private final Listener listener;
    private final ExecutorService transportEvents = Executors.newSingleThreadExecutor();
    private final ExecutorService decoderWorker = Executors.newSingleThreadExecutor();
    private final ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
    private final String installId;
    private final NsdAdvertiser advertiser;
    private final ReceiverTransport transport;
    private final ReceiverConnectionCoordinator connectionCoordinator;
    private final ReceiverProtocolSession protocolSession = new ReceiverProtocolSession();
    private final FrameSizeMetrics frameSizeMetrics = new FrameSizeMetrics();
    private volatile boolean wifiAdvertisingEnabled;
    private volatile int listeningPort;
    private volatile DisplaySpec displaySpec;
    private volatile boolean running;
    private Surface surface;
    private volatile H264SurfaceDecoder decoder;
    private volatile long decoderGeneration;
    private volatile long decoderSessionEpoch;
    private volatile long decoderConfigVersion;
    private volatile boolean decoderAwaitingFreshConfig;
    private volatile long streamingGeneration;
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
    private long latestVideoFrameGeneration;
    private final DecodeWorkerState decodeWorkerState = new DecodeWorkerState();
    private volatile long lastVideoReceivedMs;
    private volatile long lastFrameRenderedMs;
    private volatile long lastDecoderRecoveryMs;

    public interface Listener {
        void onStatus(String status);
        void onConnected(boolean connected);
        void onStreaming(boolean streaming);
        void onConnectionState(ReceiverConnectionStateSnapshot state);
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
                        OpenDisplayServer.this.releaseDecoder();
                    }

                    @Override
                    public void setConnected(boolean connected) {
                        listener.onConnected(connected);
                    }

                    @Override
                    public void stopStreaming() {
                        listener.onStreaming(false);
                    }

                    @Override
                    public void onConnectionState(ReceiverConnectionStateSnapshot state) {
                        listener.onConnectionState(state);
                        if (protocolSession.isNegotiatedV2()) {
                            sendJson(LengthPrefixedProtocol.connectionStateJson(
                                    state.state.name(),
                                    state.reason,
                                    state.enteredAtMs,
                                    state.generation,
                                    state.sessionEpoch,
                                    state.configVersion));
                        }
                    }
                });
    }

    public void start(Surface surface) {
        if (running) {
            return;
        }
        running = true;
        this.surface = surface;
        metricsWindowStartMs = System.currentTimeMillis();
        transport.start(new ReceiverTransport.Listener() {
            @Override
            public void onListening(int port) {
                executeTransportEvent(() -> {
                    listeningPort = port;
                    if (wifiAdvertisingEnabled) {
                        startWifiAdvertising(port);
                    }
                    listener.onStatus("正在监听 :" + port + " / " + transport.name());
                });
            }

            @Override
            public void onConnected(long generation, String peer) {
                executeTransportEvent(() -> {
                    if (!connectionCoordinator.onConnected(generation, "socketAccepted")) {
                        return;
                    }
                    protocolSession.onConnected(generation);
                    frameSizeMetrics.resetCurrent();
                    resetClockSynchronization();
                    lastVideoReceivedMs = 0;
                    lastFrameRenderedMs = System.currentTimeMillis();
                    lastDecoderRecoveryMs = 0;
                    streamingGeneration = 0;
                    replaceDecoder(generation);
                    listener.onStatus("Mac 已连接：" + peer);
                    sendHello();
                });
            }

            @Override
            public void onPayload(long generation, byte[] payload) {
                executeTransportEvent(() -> {
                    if (connectionCoordinator.isCurrent(generation)) {
                        handleTransportPayload(generation, payload);
                    }
                });
            }

            @Override
            public void onFrameLengthRejected(
                    long generation, String reason, int frameBytes, int maximumBytes) {
                executeTransportEvent(() -> {
                    if (!connectionCoordinator.isCurrent(generation)) {
                        return;
                    }
                    LengthPrefixedProtocol.FrameLengthFailure failure;
                    try {
                        failure = LengthPrefixedProtocol.FrameLengthFailure.valueOf(
                                reason.toUpperCase(java.util.Locale.US));
                    } catch (IllegalArgumentException error) {
                        failure = LengthPrefixedProtocol.FrameLengthFailure.INVALID_LENGTH;
                    }
                    frameSizeMetrics.recordRejected(failure);
                    android.util.Log.w("DisplayWeave",
                            "frame length rejected generation=" + generation
                                    + " reason=" + reason
                                    + " frameBytes=" + frameBytes
                                    + " maximumBytes=" + maximumBytes);
                });
            }

            @Override
            public void onDisconnected(long generation) {
                executeTransportEvent(() -> {
                    if (!connectionCoordinator.onDisconnected(generation, "readerExited")) {
                        return;
                    }
                    resetClockSynchronization();
                    lastVideoReceivedMs = 0;
                });
            }

            @Override
            public void onError(long generation, String message) {
                executeTransportEvent(() -> {
                    if (connectionCoordinator.onError(generation, message)) {
                        listener.onStatus(message);
                    }
                });
            }
        });
        timer.scheduleAtFixedRate(this::sendPingIfConnected, 2, 2, TimeUnit.SECONDS);
        timer.scheduleAtFixedRate(this::publishStatsSafely, 1, 1, TimeUnit.SECONDS);
    }

    public void stop() {
        running = false;
        listeningPort = 0;
        advertiser.stop();
        transport.stop(LengthPrefixedProtocol.goodbyeJson().getBytes(StandardCharsets.UTF_8));
        resetQueuedFrames();
        releaseDecoderImmediately();
        transportEvents.shutdownNow();
        decoderWorker.shutdownNow();
        timer.shutdownNow();
    }

    public void updateDisplay(DisplaySpec spec) {
        displaySpec = spec;
        executeTransportEvent(this::sendHello);
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

    private void executeTransportEvent(Runnable event) {
        if (!running) {
            return;
        }
        try {
            transportEvents.execute(() -> {
                if (running) {
                    event.run();
                }
            });
        } catch (java.util.concurrent.RejectedExecutionException ignored) {
            // stop() may race with a final transport callback.
        }
    }

    private void enqueueVideoFrame(long generation, byte[] payload) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        lastVideoReceivedMs = System.currentTimeMillis();
        VideoFrameTelemetry telemetry = VideoFrameTelemetry.fromWirePayload(
                payload, System.currentTimeMillis());
        if (!protocolSession.acceptFrame(generation, telemetry)) {
            return;
        }
        frameSizeMetrics.recordFrame(
                payload.length,
                VideoFrameClassifier.isKeyframe(payload, currentStreamConfig));
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
            latestVideoFrameGeneration = generation;
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
            long generation;
            synchronized (this) {
                frame = latestVideoFrame;
                telemetry = latestVideoFrameTelemetry;
                generation = latestVideoFrameGeneration;
                latestVideoFrame = null;
                latestVideoFrameTelemetry = null;
                latestVideoFrameGeneration = 0;
                queueDepthAndroid = 0;
                if (frame == null) {
                    decodeWorkerState.markIdle();
                    return;
                }
            }
            if (!connectionCoordinator.isCurrent(generation)) {
                continue;
            }
            queueFrameIfCurrentDecoder(generation, frame, telemetry);
        }
        synchronized (this) {
            decodeWorkerState.markIdle();
        }
    }

    private void handleTransportPayload(long generation, byte[] payload) {
        if (LengthPrefixedProtocol.isPureJsonControl(payload)) {
            handleMacJson(generation, new String(payload, StandardCharsets.UTF_8));
        } else if (decoder != null) {
            enqueueVideoFrame(generation, payload);
        }
    }

    private void handleMacJson(long generation, String json) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
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
                    int protocolVersion = object.optInt("protocolVersion", 1);
                    long sessionEpoch = object.optLong("sessionEpoch", 0);
                    long configVersion = object.optLong("configVersion", 0);
                    if (!protocolSession.acceptStreamConfig(
                            generation, protocolVersion, sessionEpoch, configVersion)) {
                        android.util.Log.w("DisplayWeave", "rejected stale/invalid streamConfig"
                                + " generation=" + generation
                                + " sessionEpoch=" + sessionEpoch
                                + " configVersion=" + configVersion);
                        return;
                    }
                    int negotiatedMaxFrameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES;
                    if (protocolSession.isNegotiatedV2()) {
                        int requestedMaxFrameBytes = object.optInt(
                                "maxFrameBytes",
                                LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES);
                        negotiatedMaxFrameBytes =
                                LengthPrefixedProtocol.negotiatedV2FrameLimit(
                                        requestedMaxFrameBytes);
                    }
                    transport.setMaxFrameBytes(generation, negotiatedMaxFrameBytes);
                    resetQueuedFrames();
                    if (protocolSession.isNegotiatedV2()) {
                        connectionCoordinator.transition(
                                generation,
                                ReceiverConnectionState.HELLO_ACCEPTED,
                                "protocolV2Selected",
                                sessionEpoch,
                                configVersion);
                    }
                    connectionCoordinator.transition(
                            generation,
                            ReceiverConnectionState.STREAM_CONFIG_RECEIVED,
                            "streamConfigReceived",
                            sessionEpoch,
                            configVersion);
                    VideoStreamConfig config = VideoStreamConfig.from(
                            object.optString("codec", "h264"),
                            object.optInt("fps", 60),
                            object.optInt("width", displaySpec.pixelsWide),
                            object.optInt("height", displaySpec.pixelsHigh),
                            object.optInt("bitrate", 0));
                    VideoStreamConfig previousConfig = currentStreamConfig;
                    currentStreamConfig = config;
                    lastMacTransport = object.optString("transport", lastMacTransport);
                    listener.onStreamConfig(config);
                    streamingGeneration = 0;
                    if (protocolSession.isNegotiatedV2()) {
                        sendJson(LengthPrefixedProtocol.streamConfigAckJson(
                                sessionEpoch,
                                configVersion,
                                true,
                                config.codec,
                                config.fps,
                                config.width,
                                config.height,
                                surface != null && surface.isValid()));
                        connectionCoordinator.transition(
                                generation,
                                ReceiverConnectionState.STREAM_CONFIG_ACCEPTED,
                                "streamConfigAckSent",
                                sessionEpoch,
                                configVersion);
                    }
                    connectionCoordinator.transition(
                            generation,
                            ReceiverConnectionState.DECODER_CONFIGURING,
                            "streamConfigApplied",
                            sessionEpoch,
                            configVersion);
                    configureDecoderForIdentity(
                            generation, sessionEpoch, configVersion, previousConfig, config);
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
        long generation = connectionCoordinator.currentGeneration();
        if (protocolSession.isNegotiatedV2()) {
            connectionCoordinator.transition(
                    generation,
                    ReceiverConnectionState.HELLO_SENT,
                    "helloSent",
                    protocolSession.sessionEpoch(),
                    protocolSession.configVersion());
        } else {
            connectionCoordinator.transition(
                    generation,
                    ReceiverConnectionState.HELLO_SENT,
                    "helloSent");
        }
    }

    private void sendPingIfConnected() {
        sendJson(LengthPrefixedProtocol.pingJson(LengthPrefixedProtocol.nowMs()));
    }

    private synchronized void resetClockSynchronization() {
        clockEstimator.reset();
        clockOffsetMs = null;
        lastRttMs = 0;
    }

    private void sendJson(String json) {
        long generation = connectionCoordinator.currentGeneration();
        if (connectionCoordinator.isCurrent(generation)) {
            transport.send(generation, json.getBytes(StandardCharsets.UTF_8));
        }
    }

    private synchronized void resetQueuedFrames() {
        latestVideoFrame = null;
        latestVideoFrameTelemetry = null;
        latestVideoFrameGeneration = 0;
        queueDepthAndroid = 0;
        decodeWorkerState.markQueueReset();
    }

    private synchronized void replaceDecoder(long generation) {
        releaseDecoder();
        if (surface == null || !connectionCoordinator.isCurrent(generation)) {
            return;
        }
        decoderGeneration = generation;
        decoderSessionEpoch = 0;
        decoderConfigVersion = 0;
        decoderAwaitingFreshConfig = false;
        decoder = new H264SurfaceDecoder(
                surface, new GenerationDecoderListener(generation, 0, 0));
    }

    private void configureDecoderForIdentity(
            long generation, long sessionEpoch, long configVersion,
            VideoStreamConfig previousConfig, VideoStreamConfig config) {
        H264SurfaceDecoder previous;
        GenerationDecoderListener nextListener =
                new GenerationDecoderListener(generation, sessionEpoch, configVersion);
        synchronized (this) {
            if (surface == null || !connectionCoordinator.isCurrent(generation)
                    || !protocolSession.matchesIdentity(sessionEpoch, configVersion)) {
                return;
            }
            previous = decoder;
            decoderGeneration = generation;
            decoderSessionEpoch = sessionEpoch;
            decoderConfigVersion = configVersion;
            if (previous != null
                    && !decoderAwaitingFreshConfig
                    && !DecoderReconfigurationPolicy.requiresReplacement(
                            previousConfig, config)
                    && previous.rebindIfConfigured(nextListener)) {
                return;
            }
            decoder = null;
        }

        // MediaCodec.stop()/release() can block in vendor code. Keep that work
        // off the serialized transport-event executor so Ack, ping and newer
        // stream configurations remain observable and bounded.
        decoderWorker.execute(() -> {
            if (previous != null) {
                previous.release();
            }
            H264SurfaceDecoder next;
            synchronized (OpenDisplayServer.this) {
                if (surface == null || !connectionCoordinator.isCurrent(generation)
                        || !protocolSession.matchesIdentity(sessionEpoch, configVersion)
                        || decoder != null) {
                    return;
                }
                next = new H264SurfaceDecoder(surface, nextListener);
                decoder = next;
            }
            next.applyStreamConfig(config.codec, config.fps, config.width, config.height);
            decoderAwaitingFreshConfig = false;
        });
    }

    private void releaseDecoder() {
        H264SurfaceDecoder activeDecoder;
        synchronized (this) {
            activeDecoder = detachDecoder();
        }
        if (activeDecoder != null) {
            decoderWorker.execute(activeDecoder::release);
        }
    }

    private void releaseDecoderImmediately() {
        H264SurfaceDecoder activeDecoder;
        synchronized (this) {
            activeDecoder = detachDecoder();
        }
        if (activeDecoder != null) {
            activeDecoder.release();
        }
    }

    private H264SurfaceDecoder detachDecoder() {
        H264SurfaceDecoder activeDecoder = decoder;
        decoder = null;
        decoderGeneration = 0;
        decoderSessionEpoch = 0;
        decoderConfigVersion = 0;
        decoderAwaitingFreshConfig = false;
        return activeDecoder;
    }

    private synchronized void queueFrameIfCurrentDecoder(
            long generation, byte[] frame, VideoFrameTelemetry telemetry) {
        H264SurfaceDecoder activeDecoder = decoder;
        if (activeDecoder != null && decoderGeneration == generation
                && !decoderAwaitingFreshConfig
                && protocolSession.matchesIdentity(
                        decoderSessionEpoch, decoderConfigVersion)
                && protocolSession.matchesCurrentFrame(telemetry)) {
            activeDecoder.queueFrame(frame, telemetry);
        }
    }

    private synchronized boolean releaseCodecForRecovery(
            long generation, boolean requireFreshConfig) {
        if (decoder == null || decoderGeneration != generation
                || !protocolSession.matchesIdentity(
                        decoderSessionEpoch, decoderConfigVersion)) {
            return false;
        }
        resetQueuedFrames();
        H264SurfaceDecoder activeDecoder = decoder;
        decoderAwaitingFreshConfig = requireFreshConfig;
        decoderWorker.execute(activeDecoder::release);
        return true;
    }

    private final class GenerationDecoderListener implements H264SurfaceDecoder.Listener {
        private final long generation;
        private final long sessionEpoch;
        private final long configVersion;

        GenerationDecoderListener(long generation, long sessionEpoch, long configVersion) {
            this.generation = generation;
            this.sessionEpoch = sessionEpoch;
            this.configVersion = configVersion;
        }

        private boolean isCurrentIdentity() {
            return connectionCoordinator.isCurrent(generation)
                    && protocolSession.matchesIdentity(sessionEpoch, configVersion);
        }

        @Override
        public void onDecoderStatus(String status) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderStatus(generation, status);
                }
            });
        }

        @Override
        public void onDecoderReady(DecoderRuntimeInfo info) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderReady(generation, info);
                }
            });
        }

        @Override
        public void onDecoderNeedsKeyframe() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderNeedsKeyframe(generation);
                }
            });
        }

        @Override
        public void onDecoderCodecFailure(String codec, String message) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderCodecFailure(generation, codec, message);
                }
            });
        }

        @Override
        public void onDecoderFrameDropped() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderFrameDropped(generation);
                }
            });
        }

        @Override
        public void onDecoderFrameDecoded() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderFrameDecoded(generation);
                }
            });
        }

        @Override
        public void onDecoderFrameRendered(VideoFrameTelemetry telemetry) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderFrameRendered(generation, telemetry);
                }
            });
        }
    }

    private void onDecoderStatus(long generation, String status) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        android.util.Log.i("DisplayWeaveDecoder", "generation=" + generation
                + " status=" + status);
        if (status.contains("失败") || status.contains("异常")
                || status.contains("过大") || status.startsWith("无法")) {
            listener.onStatus(status);
        }
    }

    private void onDecoderReady(long generation, DecoderRuntimeInfo info) {
        long sessionEpoch = protocolSession.sessionEpoch();
        long configVersion = protocolSession.configVersion();
        if (!connectionCoordinator.transition(
                generation, ReceiverConnectionState.DECODER_READY, "mediaCodecStarted",
                sessionEpoch, configVersion)) {
            return;
        }
        if (protocolSession.isNegotiatedV2()) {
            sendJson(LengthPrefixedProtocol.decoderReadyJson(
                    sessionEpoch,
                    configVersion,
                    info.codec,
                    info.decoderName,
                    info.hardwareAccelerated,
                    info.softwareOnly,
                    info.lowLatencySupported,
                    info.lowLatencyEnabled));
        }
        connectionCoordinator.transition(
                generation, ReceiverConnectionState.WAITING_FIRST_FRAME, "decoderReady",
                sessionEpoch, configVersion);
    }

    private void onDecoderNeedsKeyframe(long generation) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        sendJson(LengthPrefixedProtocol.keyframeRequestJson());
    }

    private void onDecoderCodecFailure(long generation, String codec, String message) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        String fallbackStatus = CodecFallbackStatus.messageForCodecFailure(codec);
        if (fallbackStatus != null) {
            listener.onStatus(fallbackStatus);
        }
        sendJson(LengthPrefixedProtocol.codecFailureJson(codec, message));
    }

    private synchronized void onDecoderFrameDropped(long generation) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        droppedFramesAndroid++;
    }

    private synchronized void onDecoderFrameDecoded(long generation) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        decodedFrames++;
    }

    private synchronized void onDecoderFrameRendered(
            long generation, VideoFrameTelemetry telemetry) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        if (!protocolSession.matchesCurrentFrame(telemetry)) {
            return;
        }
        if (streamingGeneration != generation) {
            streamingGeneration = generation;
            long sessionEpoch = protocolSession.sessionEpoch();
            long configVersion = protocolSession.configVersion();
            connectionCoordinator.transition(
                    generation, ReceiverConnectionState.STREAMING, "firstFrameRendered",
                    sessionEpoch, configVersion);
            if (protocolSession.isNegotiatedV2()) {
                sendJson(LengthPrefixedProtocol.firstFrameRenderedJson(
                        sessionEpoch, configVersion, telemetry.frameSequence));
            }
            listener.onStreaming(true);
        }
        renderedFrames++;
        long now = System.currentTimeMillis();
        lastFrameRenderedMs = now;
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
        executeTransportEvent(() -> {
            try {
                recoverDecoderIfStalled(System.currentTimeMillis());
                publishStatsIfDue();
            } catch (RuntimeException error) {
                android.util.Log.w("DisplayWeave", "stats publication failed", error);
            }
        });
    }

    private void recoverDecoderIfStalled(long nowMs) {
        long generation = connectionCoordinator.currentGeneration();
        if (!running || !connectionCoordinator.isCurrent(generation)
                || !DecoderStallRecoveryPolicy.shouldRecover(
                nowMs, lastVideoReceivedMs, lastFrameRenderedMs, lastDecoderRecoveryMs)) {
            return;
        }
        lastDecoderRecoveryMs = nowMs;
        boolean negotiatedV2 = protocolSession.isNegotiatedV2();
        if (!releaseCodecForRecovery(generation, negotiatedV2)) {
            return;
        }
        streamingGeneration = 0;
        connectionCoordinator.transition(
                generation, ReceiverConnectionState.RECOVERING, "decoderStalled");
        listener.onStatus("检测到画面停滞，正在重建解码器…");
        sendJson(LengthPrefixedProtocol.decoderResetRequestJson(negotiatedV2));
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
            FrameSizeMetrics.Snapshot frameSizes = frameSizeMetrics.snapshot();
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
                    lastInputP95Ms > 0 ? lastInputP95Ms : null,
                    frameSizes.currentFrameBytes,
                    frameSizes.maxFrameBytesObserved,
                    frameSizes.currentKeyframeBytes,
                    frameSizes.maxKeyframeBytesObserved,
                    frameSizes.oversizeFrameCount,
                    frameSizes.invalidFrameLengthCount);
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
