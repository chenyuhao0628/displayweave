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
import app.opendisplay.android.protocol.BinaryFrameHeaderV2;

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
    private final FrameAllocationMetrics frameAllocationMetrics =
            new FrameAllocationMetrics();
    private final AndroidPowerMetrics powerMetrics;
    private final AndroidDropTracker androidDropTracker = new AndroidDropTracker();
    private DecoderLowLatencyMode decoderLowLatencyMode = DecoderLowLatencyMode.AUTO;
    private volatile boolean wifiAdvertisingEnabled;
    private volatile int listeningPort;
    private volatile DisplaySpec displaySpec;
    private volatile boolean running;
    private Surface surface;
    private volatile H264SurfaceDecoder decoder;
    private volatile DecoderRuntimeInfo decoderRuntimeInfo;
    private volatile long decoderGeneration;
    private volatile long decoderSessionEpoch;
    private volatile long decoderConfigVersion;
    private volatile boolean decoderAwaitingFreshConfig;
    private volatile long streamingGeneration;
    private volatile Double clockOffsetMs;
    private final ClockOffsetEstimator clockEstimator = new ClockOffsetEstimator(8);
    private int renderedFrames;
    private int decodedFrames;
    private int receivedFrames;
    private int submittedToMediaCodecFrames;
    private int pendingSlotReplaceCount;
    private int referenceChainBreakCount;
    private int keyframeRequestCount;
    private int keyframeReceivedCount;
    private long awaitingKeyframeDurationMs;
    private long decoderRecoveryStartedAtMs;
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
    private int lastMacPendingEncodes;
    private int lastMacTotalPendingWork;
    private int lastMacPendingEncodePeak;
    private int lastMacDroppedFrames;
    private String lastMacTransport = "wifi";
    private VideoStreamConfig currentStreamConfig = VideoStreamConfig.DEFAULT;
    private final BoundedOrderedQueue<QueuedVideoFrame> pendingVideoFrames =
            new BoundedOrderedQueue<>(FrameQueuePolicy.MAX_PENDING_FRAMES);
    private final ReferenceChainRecovery referenceChainRecovery =
            new ReferenceChainRecovery();
    private final DecodeWorkerState decodeWorkerState = new DecodeWorkerState();
    private volatile long lastVideoReceivedMs;
    private volatile long lastFrameRenderedMs;
    private volatile long lastDecoderRecoveryMs;

    private static final class QueuedVideoFrame {
        final long generation;
        final VideoFramePacket frame;

        QueuedVideoFrame(long generation, VideoFramePacket frame) {
            this.generation = generation;
            this.frame = frame;
        }
    }

    public interface Listener {
        void onStatus(String status);
        void onConnected(boolean connected);
        void onStreaming(boolean streaming);
        void onConnectionState(ReceiverConnectionStateSnapshot state);
        void onCursor(double x, double y, boolean visible);
        void onCursorImage(byte[] png, double anchorX, double anchorY,
                           double normalizedWidth, double normalizedHeight);
        void onStreamConfig(VideoStreamConfig config);
        void onTransportChanged(String transport);
        float currentDisplayRefreshRate();
        float requestedSurfaceFrameRate();
        String surfaceFrameRateApplyResult();
        WifiLowLatencyLifecycle.Snapshot wifiLowLatencySnapshot();
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
        this.powerMetrics = new AndroidPowerMetrics(context);
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
                    decoderRuntimeInfo = null;
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
                    recordDrop(AndroidDropReason.INVALID_FRAME_LENGTH,
                            generation, null);
                    android.util.Log.w("DisplayWeave",
                            "frame length rejected generation=" + generation
                                    + " reason=" + reason
                                    + " frameBytes=" + frameBytes
                                    + " maximumBytes=" + maximumBytes);
                });
            }

            @Override
            public void onTransportDrop(long generation, String reason) {
                executeTransportEvent(() -> {
                    if (!connectionCoordinator.isCurrent(generation)) {
                        return;
                    }
                    AndroidDropReason classified = "transportWriteFailure".equals(reason)
                            ? AndroidDropReason.TRANSPORT_WRITE_FAILURE
                            : AndroidDropReason.TRANSPORT_READ_FAILURE;
                    recordDrop(classified, generation, null);
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

    public synchronized void setDecoderLowLatencyMode(DecoderLowLatencyMode mode) {
        if (running) {
            throw new IllegalStateException(
                    "decoder low-latency mode must be set before start");
        }
        decoderLowLatencyMode = mode == null ? DecoderLowLatencyMode.AUTO : mode;
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
        Double offset = clockOffsetMs;
        Double macTime = offset == null ? null : LengthPrefixedProtocol.nowMs() + offset;
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
        VideoFramePacket frame;
        try {
            frame = VideoFramePacket.parse(
                    payload, System.currentTimeMillis(), currentStreamConfig);
        } catch (BinaryFrameHeaderV2.ParseException error) {
            AndroidDropReason reason = error.failure
                    == BinaryFrameHeaderV2.Failure.INVALID_PAYLOAD_LENGTH
                    || error.failure == BinaryFrameHeaderV2.Failure.OVERSIZE_PAYLOAD
                    ? AndroidDropReason.INVALID_FRAME_LENGTH
                    : AndroidDropReason.MALFORMED_ANNEX_B;
            recordDrop(reason, generation, null);
            return;
        }
        VideoFrameTelemetry telemetry = frame.telemetry;
        if (frame.binaryHeaderV2 && !protocolSession.isNegotiatedV2()) {
            recordDrop(AndroidDropReason.MALFORMED_ANNEX_B, generation, telemetry);
            return;
        }
        if (!frame.hasAnnexBPayload()) {
            recordDrop(AndroidDropReason.MALFORMED_ANNEX_B, generation, telemetry);
            return;
        }
        frameAllocationMetrics.recordTransportFrame(
                payload.length, frame.bytes == payload);
        lastVideoReceivedMs = System.currentTimeMillis();
        AndroidDropReason rejection =
                protocolSession.frameRejectionReason(generation, telemetry);
        if (rejection != null) {
            if (rejection != AndroidDropReason.STALE_CONNECTION_GENERATION) {
                recordDrop(rejection, generation, telemetry);
            }
            return;
        }
        if (!frame.codecMatches(currentStreamConfig)) {
            recordDrop(AndroidDropReason.MALFORMED_ANNEX_B, generation, telemetry);
            return;
        }
        if (!protocolSession.acceptFrame(generation, telemetry)) {
            recordDrop(AndroidDropReason.STALE_CONFIG_VERSION, generation, telemetry);
            return;
        }
        frameSizeMetrics.recordFrame(
                frame.payloadLength, frame.keyframe);
        synchronized (this) {
            receivedFrames++;
            if (frame.keyframe) {
                keyframeReceivedCount++;
            }
            boolean wasAwaitingKeyframe = referenceChainRecovery.isAwaitingKeyframe();
            if (referenceChainRecovery.shouldReject(
                    frame.keyframe, System.currentTimeMillis())) {
                recordDrop(AndroidDropReason.AWAITING_KEYFRAME_REJECTED,
                        generation, telemetry);
                return;
            }
            if (wasAwaitingKeyframe && frame.keyframe) {
                awaitingKeyframeDurationMs +=
                        referenceChainRecovery.lastCompletedDurationMs();
            }
            if (!pendingVideoFrames.offer(new QueuedVideoFrame(generation, frame))) {
                pendingSlotReplaceCount++;
                for (QueuedVideoFrame dropped : pendingVideoFrames.clearAndReturn()) {
                    recordDrop(AndroidDropReason.LATEST_SLOT_REPLACED,
                            dropped.generation, dropped.frame.telemetry);
                }
                queueDepthAndroid = 0;
                if (!frame.keyframe) {
                    breakReferenceChain(generation, telemetry);
                    return;
                }
                pendingVideoFrames.offer(new QueuedVideoFrame(generation, frame));
            }
            queueDepthAndroid = pendingVideoFrames.size();
            if (decodeWorkerState.markFrameAvailable()) {
                decoderWorker.execute(this::drainLatestVideoFrames);
            }
        }
    }

    private void drainLatestVideoFrames() {
        boolean requestRecovery = false;
        try {
            while (running) {
                QueuedVideoFrame queued;
                synchronized (this) {
                    queued = pendingVideoFrames.poll();
                    queueDepthAndroid = pendingVideoFrames.size();
                    if (queued == null) {
                        return;
                    }
                }
                if (!connectionCoordinator.isCurrent(queued.generation)) {
                    continue;
                }
                queueFrameIfCurrentDecoder(queued.generation, queued.frame);
            }
        } catch (RuntimeException error) {
            android.util.Log.e(
                    "DisplayWeave", "decoder worker dropped a malformed frame", error);
            requestRecovery = true;
        } finally {
            boolean reschedule;
            synchronized (this) {
                reschedule = decodeWorkerState.markIdleAndCheckForPendingFrame(
                        running && !pendingVideoFrames.isEmpty());
            }
            if (reschedule) {
                decoderWorker.execute(this::drainLatestVideoFrames);
            }
            if (requestRecovery) {
                requestKeyframe();
            }
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
        String messageType = "unknown";
        boolean streamConfigCommitted = false;
        try {
            JSONObject object = new JSONObject(json);
            String type = object.optString("type", "");
            messageType = type;
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
                lastMacPendingEncodes = object.optInt(
                        "pendingEncodesMac", lastMacPendingEncodes);
                lastMacTotalPendingWork = object.optInt(
                        "totalPendingWorkMac",
                        lastMacQueueDepth + lastMacPendingEncodes);
                lastMacPendingEncodePeak = object.optInt(
                        "pendingEncodePeak", lastMacPendingEncodePeak);
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
                    DisplaySpec activeDisplaySpec = displaySpec;
                    if (activeDisplaySpec == null) {
                        throw new IllegalStateException("streamConfig received without display spec");
                    }
                    VideoStreamConfig config = VideoStreamConfig.from(
                            object.optString("codec", "h264"),
                            object.optInt("fps", 60),
                            object.optInt("width", activeDisplaySpec.pixelsWide),
                            object.optInt("height", activeDisplaySpec.pixelsHigh),
                            object.optInt("bitrate", 0));
                    if (config.width <= 0 || config.height <= 0) {
                        throw new IllegalArgumentException(
                                "invalid stream dimensions " + config.width + "x" + config.height);
                    }
                    boolean requestedV2 = protocolVersion >= 2;
                    int negotiatedMaxFrameBytes = LengthPrefixedProtocol.LEGACY_MAX_FRAME_BYTES;
                    if (requestedV2) {
                        int requestedMaxFrameBytes = object.optInt(
                                "maxFrameBytes",
                                LengthPrefixedProtocol.V2_DEFAULT_MAX_FRAME_BYTES);
                        negotiatedMaxFrameBytes =
                                LengthPrefixedProtocol.negotiatedV2FrameLimit(
                                        requestedMaxFrameBytes);
                    }
                    if (!protocolSession.acceptStreamConfig(
                            generation, protocolVersion, sessionEpoch, configVersion)) {
                        android.util.Log.w("DisplayWeave", "rejected stale/invalid streamConfig"
                                + " generation=" + generation
                                + " sessionEpoch=" + sessionEpoch
                                + " configVersion=" + configVersion);
                        return;
                    }
                    streamConfigCommitted = true;
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
                    VideoStreamConfig previousConfig = currentStreamConfig;
                    currentStreamConfig = config;
                    lastMacTransport = object.optString("transport", lastMacTransport);
                    listener.onTransportChanged(lastMacTransport);
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
        } catch (Exception error) {
            android.util.Log.e(
                    "DisplayWeave", "failed to handle Mac message type=" + messageType, error);
            if (streamConfigCommitted && connectionCoordinator.isCurrent(generation)) {
                requestKeyframe();
            }
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
        pendingVideoFrames.clear();
        referenceChainRecovery.reset();
        decoderRecoveryStartedAtMs = 0;
        queueDepthAndroid = 0;
        decodeWorkerState.markQueueReset();
    }

    private void breakReferenceChain(
            long generation, VideoFrameTelemetry telemetry) {
        if (!referenceChainRecovery.breakChain(System.currentTimeMillis())) {
            return;
        }
        referenceChainBreakCount++;
        recordDrop(AndroidDropReason.REFERENCE_CHAIN_BROKEN,
                generation, telemetry);
        requestKeyframe();
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
                surface, new GenerationDecoderListener(generation, 0, 0),
                decoderLowLatencyMode);
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
                next = new H264SurfaceDecoder(
                        surface, nextListener, decoderLowLatencyMode);
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
        decoderRuntimeInfo = null;
        decoderGeneration = 0;
        decoderSessionEpoch = 0;
        decoderConfigVersion = 0;
        decoderAwaitingFreshConfig = false;
        return activeDecoder;
    }

    private synchronized void queueFrameIfCurrentDecoder(
            long generation, VideoFramePacket frame) {
        VideoFrameTelemetry telemetry = frame.telemetry;
        H264SurfaceDecoder activeDecoder = decoder;
        if (activeDecoder == null) {
            recordDrop(surface == null
                            ? AndroidDropReason.SURFACE_UNAVAILABLE
                            : AndroidDropReason.CODEC_RECONFIGURE_DROP,
                    generation, telemetry);
            return;
        }
        if (decoderGeneration != generation) {
            return;
        }
        if (decoderAwaitingFreshConfig) {
            recordDrop(AndroidDropReason.CODEC_RECONFIGURE_DROP,
                    generation, telemetry);
            return;
        }
        if (!protocolSession.matchesIdentity(
                decoderSessionEpoch, decoderConfigVersion)) {
            AndroidDropReason reason = telemetry != null
                    && telemetry.sessionEpoch != protocolSession.sessionEpoch()
                    ? AndroidDropReason.STALE_SESSION_EPOCH
                    : AndroidDropReason.STALE_CONFIG_VERSION;
            recordDrop(reason, generation, telemetry);
            return;
        }
        if (!protocolSession.matchesCurrentFrame(telemetry)) {
            recordDrop(AndroidDropReason.STALE_CONFIG_VERSION,
                    generation, telemetry);
            return;
        }
        activeDecoder.queueFrame(frame);
    }

    private void recordDrop(AndroidDropReason reason, long generation,
                            VideoFrameTelemetry telemetry) {
        if (reason == null) {
            return;
        }
        long sessionEpoch = telemetry != null && telemetry.sessionEpoch >= 0
                ? telemetry.sessionEpoch : protocolSession.sessionEpoch();
        long configVersion = telemetry != null && telemetry.configVersion >= 0
                ? telemetry.configVersion : protocolSession.configVersion();
        long frameSequence = telemetry != null && telemetry.frameSequence >= 0
                ? telemetry.frameSequence : 0;
        androidDropTracker.record(reason, new AndroidDropTracker.Context(
                generation, sessionEpoch, configVersion, frameSequence,
                currentStreamConfig.codec, lastMacTransport));
    }

    private synchronized boolean releaseCodecForRecovery(
            long generation, boolean requireFreshConfig) {
        if (decoder == null || decoderGeneration != generation
                || decoderAwaitingFreshConfig
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
        public void onDecoderConfigurationFailed(DecoderRuntimeInfo info) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    decoderRuntimeInfo = info;
                    android.util.Log.w("DisplayWeaveDecoder",
                            "decoder configure failed generation=" + generation
                                    + " decoder=" + info.decoderName
                                    + " fallbackReason=" + info.fallbackReason);
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
        public void onDecoderFrameDropped(
                AndroidDropReason reason, VideoFrameTelemetry telemetry) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderFrameDropped(
                            generation, reason, telemetry);
                }
            });
        }

        @Override
        public void onDecoderFrameSubmitted() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderFrameSubmitted(generation);
                }
            });
        }

        @Override
        public void onDecoderPendingQueueOverflow() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderPendingQueueOverflow(generation);
                }
            });
        }

        @Override
        public void onDecoderRecoveryStarted() {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderRecoveryStarted(generation);
                }
            });
        }

        @Override
        public void onDecoderRecoveryCompleted(long durationMs) {
            executeTransportEvent(() -> {
                if (isCurrentIdentity()) {
                    OpenDisplayServer.this.onDecoderRecoveryCompleted(
                            generation, durationMs);
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
        decoderRuntimeInfo = info;
        if (protocolSession.isNegotiatedV2()) {
            sendJson(LengthPrefixedProtocol.decoderReadyJson(
                    sessionEpoch,
                    configVersion,
                    info.codec,
                    info.decoderName,
                    info.hardwareAccelerated,
                    info.softwareOnly,
                    info.vendor,
                    info.lowLatencySupported,
                    info.lowLatencyEnabled,
                    info.configureSuccess,
                    info.selectedDecoderMaxFps,
                    info.fallbackReason));
        }
        connectionCoordinator.transition(
                generation, ReceiverConnectionState.WAITING_FIRST_FRAME, "decoderReady",
                sessionEpoch, configVersion);
    }

    private void onDecoderNeedsKeyframe(long generation) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        requestKeyframe();
    }

    private synchronized void requestKeyframe() {
        keyframeRequestCount++;
        sendJson(LengthPrefixedProtocol.keyframeRequestJson());
    }

    private synchronized void onDecoderFrameSubmitted(long generation) {
        if (connectionCoordinator.isCurrent(generation)) {
            submittedToMediaCodecFrames++;
        }
    }

    private synchronized void onDecoderPendingQueueOverflow(long generation) {
        if (connectionCoordinator.isCurrent(generation)) {
            pendingSlotReplaceCount++;
        }
    }

    private synchronized void onDecoderRecoveryStarted(long generation) {
        if (connectionCoordinator.isCurrent(generation)) {
            referenceChainBreakCount++;
            if (decoderRecoveryStartedAtMs == 0) {
                decoderRecoveryStartedAtMs = System.currentTimeMillis();
            }
        }
    }

    private synchronized void onDecoderRecoveryCompleted(
            long generation, long durationMs) {
        if (connectionCoordinator.isCurrent(generation)) {
            if (decoderRecoveryStartedAtMs > 0) {
                awaitingKeyframeDurationMs += Math.max(
                        0, System.currentTimeMillis() - decoderRecoveryStartedAtMs);
            }
            decoderRecoveryStartedAtMs = 0;
        }
    }

    private void onDecoderCodecFailure(long generation, String codec, String message) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        boolean negotiatedV2 = protocolSession.isNegotiatedV2();
        if (!releaseCodecForRecovery(generation, negotiatedV2)) {
            return;
        }
        streamingGeneration = 0;
        connectionCoordinator.transition(
                generation, ReceiverConnectionState.RECOVERING, "decoderCodecFailure",
                protocolSession.sessionEpoch(), protocolSession.configVersion());
        String fallbackStatus = CodecFallbackStatus.messageForCodecFailure(codec);
        if (fallbackStatus != null) {
            listener.onStatus(fallbackStatus);
        }
        if ("hevc".equalsIgnoreCase(codec)) {
            sendJson(LengthPrefixedProtocol.codecFailureJson(codec, message));
        } else {
            sendJson(LengthPrefixedProtocol.decoderResetRequestJson(negotiatedV2));
        }
    }

    private synchronized void onDecoderFrameDropped(
            long generation, AndroidDropReason reason,
            VideoFrameTelemetry telemetry) {
        if (!connectionCoordinator.isCurrent(generation)) {
            return;
        }
        recordDrop(reason, generation, telemetry);
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
            int receivedFrameCount = receivedFrames;
            int decodedFrameCount = decodedFrames;
            int renderedFrameCount = renderedFrames;
            int submittedFrameCount = submittedToMediaCodecFrames;
            int slotReplaceCount = pendingSlotReplaceCount;
            int chainBreakCount = referenceChainBreakCount;
            int requestedKeyframeCount = keyframeRequestCount;
            int receivedKeyframeCount = keyframeReceivedCount;
            long recoveryDurationMs = awaitingKeyframeDurationMs
                    + referenceChainRecovery.consumeDurationMs(now);
            if (decoderRecoveryStartedAtMs > 0) {
                recoveryDurationMs += Math.max(0, now - decoderRecoveryStartedAtMs);
                decoderRecoveryStartedAtMs = now;
            }
            int renderedFps = (int) Math.round(renderedFrames * 1000.0 / elapsed);
            int decodedFps = (int) Math.round(decodedFrames * 1000.0 / elapsed);
            int receivedFps = (int) Math.round(receivedFrames * 1000.0 / elapsed);
            AndroidDropTracker.Snapshot dropSnapshot =
                    androidDropTracker.snapshotAndResetWindow();
            int dropped = (int) Math.min(
                    dropSnapshot.windowDropCount, Integer.MAX_VALUE);
            int latestFrameAgeMs = averageAndResetLatestFrameAge();
            int endToEndLatencyMs = averageAndResetEndToEndLatency();
            int decodeLatencyMs = averageAndResetDecodeLatency();
            MetricDistribution completedFrameAges = frameAgeDistribution;
            frameAgeDistribution = new MetricDistribution(240);
            renderedFrames = 0;
            decodedFrames = 0;
            receivedFrames = 0;
            submittedToMediaCodecFrames = 0;
            pendingSlotReplaceCount = 0;
            referenceChainBreakCount = 0;
            keyframeRequestCount = 0;
            keyframeReceivedCount = 0;
            awaitingKeyframeDurationMs = 0;
            metricsWindowStartMs = now;
            float actualAndroidHz = listener.currentDisplayRefreshRate();
            float requestedSurfaceFps = listener.requestedSurfaceFrameRate();
            String frameRateApplyResult = listener.surfaceFrameRateApplyResult();
            WifiLowLatencyLifecycle.Snapshot wifiLowLatency =
                    listener.wifiLowLatencySnapshot();
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
            FrameAllocationMetrics.Snapshot frameAllocations =
                    frameAllocationMetrics.snapshotAndResetWindow();
            AndroidPowerMetrics.Snapshot power = powerMetrics.sample();
            DecoderRuntimeInfo runtimeInfo = decoderRuntimeInfo;
            ReceiverStatsSnapshot snapshot = new ReceiverStatsSnapshot(
                    now,
                    spec == null ? "" : spec.deviceModel,
                    lastMacTransport,
                    currentStreamConfig.codec,
                    currentStreamConfig.width,
                    currentStreamConfig.height,
                    lastMacRequestedFps,
                    requestedSurfaceFps,
                    actualAndroidHz,
                    receivedFps,
                    decodedFps,
                    renderedFps,
                    receivedFrameCount,
                    submittedFrameCount,
                    slotReplaceCount,
                    chainBreakCount,
                    recoveryDurationMs,
                    requestedKeyframeCount,
                    receivedKeyframeCount,
                    decodedFrameCount,
                    renderedFrameCount,
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
                    lastMacPendingEncodes,
                    lastMacTotalPendingWork,
                    lastMacPendingEncodePeak,
                    lastInputP50Ms > 0 ? lastInputP50Ms : null,
                    lastInputP95Ms > 0 ? lastInputP95Ms : null,
                    frameSizes.currentFrameBytes,
                    frameSizes.maxFrameBytesObserved,
                    frameSizes.currentKeyframeBytes,
                    frameSizes.maxKeyframeBytesObserved,
                    frameSizes.oversizeFrameCount,
                    frameSizes.invalidFrameLengthCount,
                    frameAllocations.allocatedFrameBytes,
                    frameAllocations.bufferReuseCount,
                    frameAllocations.bufferPoolMiss,
                    frameAllocations.gcCount,
                    frameAllocations.gcTimeMs,
                    power.thermalStatus,
                    power.powerSaver,
                    power.batteryTemperature,
                    power.batteryLevel,
                    power.charging,
                    runtimeInfo == null ? null : runtimeInfo.decoderName,
                    runtimeInfo == null ? null : runtimeInfo.hardwareAccelerated,
                    runtimeInfo == null ? null : runtimeInfo.softwareOnly,
                    runtimeInfo == null ? null : runtimeInfo.vendor,
                    runtimeInfo == null ? null : runtimeInfo.lowLatencySupported,
                    runtimeInfo == null ? null : runtimeInfo.lowLatencyEnabled,
                    runtimeInfo == null ? null : runtimeInfo.configureSuccess,
                    runtimeInfo == null ? null : runtimeInfo.selectedDecoderMaxFps,
                    runtimeInfo == null ? null : runtimeInfo.fallbackReason,
                    decoderLowLatencyMode.key,
                    frameRateApplyResult,
                    wifiLowLatency == null ? "auto" : wifiLowLatency.mode,
                    wifiLowLatency != null && wifiLowLatency.requested,
                    wifiLowLatency != null && wifiLowLatency.acquired,
                    wifiLowLatency != null && wifiLowLatency.active,
                    wifiLowLatency == null
                            ? "stateUnavailable" : wifiLowLatency.releaseReason,
                    dropSnapshot);
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
