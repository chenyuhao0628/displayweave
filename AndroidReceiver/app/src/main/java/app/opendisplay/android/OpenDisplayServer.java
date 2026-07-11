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
    private volatile DisplaySpec displaySpec;
    private volatile boolean running;
    private H264SurfaceDecoder decoder;
    private Double clockOffsetMs;
    private int renderedFrames;
    private int decodedFrames;
    private int receivedFrames;
    private int droppedFramesAndroid;
    private int queueDepthAndroid;
    private long latestFrameAgeMsSum;
    private int latestFrameAgeSamples;
    private long endToEndLatencyMsSum;
    private int endToEndLatencySamples;
    private long decodeLatencyMsSum;
    private int decodeLatencySamples;
    private long metricsWindowStartMs;
    private double lastRttMs;
    private double lastInputP50Ms;
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
        this(context, displaySpec, listener, new WifiTcpReceiverTransport(PORT));
    }

    OpenDisplayServer(Context context, DisplaySpec displaySpec, Listener listener,
                      ReceiverTransport transport) {
        this.displaySpec = displaySpec;
        this.listener = listener;
        this.transport = transport;
        this.installId = InstallId.get(context);
        this.advertiser = new NsdAdvertiser(context, this);
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
                advertiser.start("DisplayWeave Android", installId, port);
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
    }

    public void stop() {
        running = false;
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

    public void sendTouch(String phase, double x, double y) {
        Double macTime = clockOffsetMs == null ? null : LengthPrefixedProtocol.nowMs() + clockOffsetMs;
        sendJson(LengthPrefixedProtocol.touchJson(phase, x, y, macTime));
    }

    public void sendScroll(double dx, double dy) {
        sendJson(LengthPrefixedProtocol.scrollJson(dx, dy));
    }

    private void enqueueVideoFrame(byte[] payload) {
        receivedFrames++;
        VideoFrameTelemetry telemetry = VideoFrameTelemetry.fromWirePayload(
                payload, System.currentTimeMillis());
        synchronized (this) {
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
                lastInputP50Ms = object.optDouble("inp50", lastInputP50Ms);
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
    public void onDecoderFrameDropped() {
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
            latestFrameAgeMsSum += telemetry.latestFrameAgeMs(now);
            latestFrameAgeSamples++;
            long endToEndLatencyMs = telemetry.endToEndLatencyMs(now, clockOffsetMs);
            if (endToEndLatencyMs >= 0) {
                this.endToEndLatencyMsSum += endToEndLatencyMs;
                endToEndLatencySamples++;
            }
            long decodeLatencyMs = telemetry.decodeLatencyMs(now, clockOffsetMs);
            if (decodeLatencyMs >= 0) {
                this.decodeLatencyMsSum += decodeLatencyMs;
                decodeLatencySamples++;
            }
        }
        long elapsed = now - metricsWindowStartMs;
        if (elapsed >= 1000) {
            int renderedFps = (int) Math.round(renderedFrames * 1000.0 / elapsed);
            int decodedFps = (int) Math.round(decodedFrames * 1000.0 / elapsed);
            int receivedFps = (int) Math.round(receivedFrames * 1000.0 / elapsed);
            int dropped = droppedFramesAndroid;
            int latestFrameAgeMs = averageAndResetLatestFrameAge();
            int endToEndLatencyMs = averageAndResetEndToEndLatency();
            int decodeLatencyMs = averageAndResetDecodeLatency();
            renderedFrames = 0;
            decodedFrames = 0;
            receivedFrames = 0;
            droppedFramesAndroid = 0;
            metricsWindowStartMs = now;
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
                    listener.currentDisplayRefreshRate(),
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
