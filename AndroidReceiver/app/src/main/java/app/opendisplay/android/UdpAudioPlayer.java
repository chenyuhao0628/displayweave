package app.opendisplay.android;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;
import android.media.MediaCodec;
import android.media.MediaFormat;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.ArrayDeque;

import app.opendisplay.android.protocol.UdpMediaProtocol;

/**
 * Unified low-latency audio playback engine for {@code udpAudioV1}, {@code tcpAudioV1},
 * and {@code audioOpusV1}.
 *
 * <p>Uses a bounded 120ms S16LE ring buffer (5,760 stereo frames @ 48kHz), dynamically
 * steers its playout watermark ({@code 15ms..90ms}) to match the active video pipeline
 * hold/decode delay with {@code target + 25ms} drift trimming, and decodes {@code formatOpus}
 * packets on the playback worker thread via Android {@link MediaCodec}.
 */
public final class UdpAudioPlayer implements AutoCloseable {
    public static final int MAX_RING_BUFFER_MS = 120;
    static final int MAX_ENCODED_QUEUE_PACKETS = 16;
    static final long OPUS_PRE_SKIP_NS = 0L;
    static final long OPUS_SEEK_PREROLL_NS = 80_000_000L;

    /**
     * Bounded A/V lip-sync playout watermark policy matching Apple {@code AudioLipSyncPolicy}.
     * Cancels sender-receiver wall-clock offset identically via relative transit deltas:
     * {@code (videoRenderMonoMs - videoCaptureMs) - (audioArrivalMonoMs - audioCaptureMs)}.
     */
    static final class LipSyncPolicy {
        static final int MAX_CAPACITY_MS = MAX_RING_BUFFER_MS;
        static final double MIN_TARGET_MS = 15.0;
        static final double MAX_TARGET_MS = 90.0;
        static final double DEFAULT_WIRED_TARGET_MS = 20.0;
        static final double DEFAULT_UDP_TARGET_MS = 45.0;
        static final double DRIFT_TOLERANCE_MS = 25.0;

        private boolean udpJitterActive;
        private double targetDelayMs = DEFAULT_WIRED_TARGET_MS;
        private boolean hasVideoSample;
        private long lastVideoCaptureMs;
        private double lastVideoRenderMonoMs;

        static double clampTargetMs(double rawMs) {
            if (!Double.isFinite(rawMs)) {
                return DEFAULT_WIRED_TARGET_MS;
            }
            return Math.max(MIN_TARGET_MS, Math.min(MAX_TARGET_MS, rawMs));
        }

        void updateVideoPipelineDelay(boolean udpActive, double explicitDelayMs) {
            boolean modeChanged = (this.udpJitterActive != udpActive);
            this.udpJitterActive = udpActive;
            double baseMs = (Double.isFinite(explicitDelayMs) && explicitDelayMs >= 0.0)
                    ? clampTargetMs(explicitDelayMs)
                    : (udpActive ? DEFAULT_UDP_TARGET_MS : DEFAULT_WIRED_TARGET_MS);
            if (modeChanged) {
                targetDelayMs = baseMs;
            } else {
                targetDelayMs = clampTargetMs(targetDelayMs * 0.7 + baseMs * 0.3);
            }
        }

        void recordVideoRender(long videoCaptureMs, double renderMonoMs) {
            if (videoCaptureMs <= 0 || !Double.isFinite(renderMonoMs)) {
                return;
            }
            this.lastVideoCaptureMs = videoCaptureMs;
            this.lastVideoRenderMonoMs = renderMonoMs;
            this.hasVideoSample = true;
        }

        void recordAudioArrival(long audioCaptureMs, double arrivalMonoMs) {
            if (!hasVideoSample || audioCaptureMs <= 0 || !Double.isFinite(arrivalMonoMs)) {
                return;
            }
            if (Math.abs(audioCaptureMs - lastVideoCaptureMs) > 2_000L) {
                return;
            }
            double videoTransitPlusHoldMs = lastVideoRenderMonoMs - (double) lastVideoCaptureMs;
            double audioTransitMs = arrivalMonoMs - (double) audioCaptureMs;
            double relativeVideoLeadMs = videoTransitPlusHoldMs - audioTransitMs;
            if (!Double.isFinite(relativeVideoLeadMs)
                    || relativeVideoLeadMs < -50.0
                    || relativeVideoLeadMs > 250.0) {
                return;
            }
            double desiredMs = clampTargetMs(Math.max(0.0, relativeVideoLeadMs));
            targetDelayMs = clampTargetMs(targetDelayMs * 0.85 + desiredMs * 0.15);
        }

        double targetMs() {
            return targetDelayMs;
        }

        boolean isUdpJitterActive() {
            return udpJitterActive;
        }

        int targetFrames(int sampleRate) {
            int safeRate = Math.max(8_000, sampleRate);
            return Math.max(1, (int) Math.round((safeRate * targetDelayMs) / 1_000.0));
        }

        int targetBytes(int sampleRate, int channels) {
            int frameSize = Math.max(2, channels * 2);
            return targetFrames(sampleRate) * frameSize;
        }

        int driftTrimThresholdBytes(int sampleRate, int channels) {
            int safeRate = Math.max(8_000, sampleRate);
            int frameSize = Math.max(2, channels * 2);
            int capBytes = PcmRingBuffer.capacityBytesFor(safeRate, channels);
            double trimMs = Math.min(MAX_CAPACITY_MS - 5.0, targetDelayMs + DRIFT_TOLERANCE_MS);
            int rawBytes = Math.max(frameSize, (int) Math.round((safeRate * trimMs) / 1_000.0) * frameSize);
            return Math.min(capBytes, rawBytes);
        }

        void reset() {
            udpJitterActive = false;
            targetDelayMs = DEFAULT_WIRED_TARGET_MS;
            hasVideoSample = false;
            lastVideoCaptureMs = 0L;
            lastVideoRenderMonoMs = 0.0;
        }
    }

    /** Builds the 19-byte RFC 7845 {@code OpusHead} identification header for MediaCodec {@code csd-0}. */
    static byte[] buildOpusHead(int sampleRate, int channels) {
        int safeChannels = (channels == 1) ? 1 : 2;
        int safeRate = (sampleRate > 0) ? sampleRate : 48_000;
        ByteBuffer header = ByteBuffer.allocate(19).order(ByteOrder.LITTLE_ENDIAN);
        header.put((byte) 'O');
        header.put((byte) 'p');
        header.put((byte) 'u');
        header.put((byte) 's');
        header.put((byte) 'H');
        header.put((byte) 'e');
        header.put((byte) 'a');
        header.put((byte) 'd');
        header.put((byte) 1); // version = 1
        header.put((byte) safeChannels);
        header.putShort((short) 0); // pre-skip = 0 samples
        header.putInt(safeRate);
        header.putShort((short) 0); // output gain = 0 dB
        header.put((byte) 0); // channel mapping family = 0
        return header.array();
    }

    /** Builds an 8-byte little-endian {@code int64} CSD buffer ({@code csd-1} pre-skip / {@code csd-2} pre-roll). */
    static byte[] buildLittleEndianLongCsd(long valueNs) {
        return ByteBuffer.allocate(8).order(ByteOrder.LITTLE_ENDIAN).putLong(valueNs).array();
    }

    /** Pure-Java bounded S16LE ring buffer with frame-aligned overflow & lip-sync drift trimming (120ms cap). */
    static final class PcmRingBuffer {
        private byte[] buffer;
        private int sampleRate;
        private int channels;
        private int frameBytes;
        private int readPos;
        private int size;
        private Long lastAudioSeq;
        private long droppedOverflowBytes;
        private long driftTrimmedBytes;
        private boolean primed;

        PcmRingBuffer(int sampleRate, int channels) {
            reconfigure(sampleRate, channels);
        }

        static int capacityBytesFor(int sampleRate, int channels) {
            int frameSize = Math.max(2, channels * 2);
            long rawBytes = ((long) sampleRate * frameSize * MAX_RING_BUFFER_MS) / 1_000L;
            long aligned = (rawBytes / frameSize) * frameSize;
            return (int) Math.max(frameSize, aligned);
        }

        void reconfigure(int nextSampleRate, int nextChannels) {
            this.sampleRate = nextSampleRate;
            this.channels = nextChannels;
            this.frameBytes = Math.max(2, nextChannels * 2);
            this.buffer = new byte[capacityBytesFor(nextSampleRate, nextChannels)];
            this.readPos = 0;
            this.size = 0;
            this.lastAudioSeq = null;
            this.primed = false;
        }

        int sampleRate() {
            return sampleRate;
        }

        int channels() {
            return channels;
        }

        int capacityBytes() {
            return buffer.length;
        }

        int availableBytes() {
            return size;
        }

        long droppedOverflowBytes() {
            return droppedOverflowBytes;
        }

        long driftTrimmedBytes() {
            return driftTrimmedBytes;
        }

        boolean isPrimed() {
            return primed;
        }

        boolean acceptPacketMetadata(long audioSeq, int packetSampleRate, int packetChannels) {
            if (packetSampleRate != sampleRate || packetChannels != channels) {
                reconfigure(packetSampleRate, packetChannels);
            } else if (lastAudioSeq != null
                    && UdpMediaProtocol.compareFrameId(audioSeq, lastAudioSeq) <= 0) {
                return false;
            }
            lastAudioSeq = audioSeq;
            return true;
        }

        boolean offerPacket(UdpMediaProtocol.AudioPayload packet) {
            if (packet == null || packet.pcmBytes == null || packet.pcmBytes.length == 0
                    || packet.formatFlags != UdpMediaProtocol.AudioPayload.FORMAT_S16LE_PCM) {
                return false;
            }
            if (!acceptPacketMetadata(packet.audioSeq, packet.sampleRate, packet.channels)) {
                return false;
            }
            writeBounded(packet.pcmBytes, 0, packet.pcmBytes.length);
            return true;
        }

        void writeBounded(byte[] pcm, int offset, int length) {
            int alignedLen = (length / frameBytes) * frameBytes;
            if (alignedLen <= 0) {
                return;
            }
            int capacity = buffer.length;
            if (alignedLen >= capacity) {
                int skip = alignedLen - capacity;
                droppedOverflowBytes += size + skip;
                System.arraycopy(pcm, offset + skip, buffer, 0, capacity);
                readPos = 0;
                size = capacity;
                return;
            }
            int overflow = (size + alignedLen) - capacity;
            if (overflow > 0) {
                int dropAligned = ((overflow + frameBytes - 1) / frameBytes) * frameBytes;
                dropAligned = Math.min(size, dropAligned);
                readPos = (readPos + dropAligned) % capacity;
                size -= dropAligned;
                droppedOverflowBytes += dropAligned;
            }
            int writePos = (readPos + size) % capacity;
            int firstChunk = Math.min(alignedLen, capacity - writePos);
            System.arraycopy(pcm, offset, buffer, writePos, firstChunk);
            if (firstChunk < alignedLen) {
                System.arraycopy(pcm, offset + firstChunk, buffer, 0, alignedLen - firstChunk);
            }
            size += alignedLen;
        }

        void applyLipSyncWatermark(int targetBytes, int trimThresholdBytes) {
            int alignedTarget = Math.max(frameBytes, (targetBytes / frameBytes) * frameBytes);
            int alignedThreshold = Math.max(alignedTarget, (trimThresholdBytes / frameBytes) * frameBytes);
            if (size <= alignedThreshold) {
                return;
            }
            int excess = size - alignedTarget;
            int dropAligned = (excess / frameBytes) * frameBytes;
            if (dropAligned <= 0) {
                return;
            }
            dropAligned = Math.min(size, dropAligned);
            readPos = (readPos + dropAligned) % buffer.length;
            size -= dropAligned;
            driftTrimmedBytes += dropAligned;
        }

        int drain(byte[] out, int maxLength) {
            if (size == 0 || out == null || maxLength < frameBytes) {
                return 0;
            }
            int alignedMax = (Math.min(maxLength, out.length) / frameBytes) * frameBytes;
            int toRead = Math.min(size, alignedMax);
            if (toRead <= 0) {
                return 0;
            }
            int capacity = buffer.length;
            int firstChunk = Math.min(toRead, capacity - readPos);
            System.arraycopy(buffer, readPos, out, 0, firstChunk);
            if (firstChunk < toRead) {
                System.arraycopy(buffer, 0, out, firstChunk, toRead - firstChunk);
            }
            readPos = (readPos + toRead) % capacity;
            size -= toRead;
            if (size == 0) {
                primed = false;
            }
            return toRead;
        }

        int drainPrimed(byte[] out, int maxLength, int targetBytes, boolean flushTail) {
            if (size == 0) {
                primed = false;
                return 0;
            }
            int effectiveTarget = Math.max(
                    frameBytes,
                    Math.min(buffer.length, (targetBytes / frameBytes) * frameBytes));
            if (!primed && !flushTail) {
                if (size < effectiveTarget) {
                    return 0;
                }
                primed = true;
            }
            return drain(out, maxLength);
        }

        void clear() {
            readPos = 0;
            size = 0;
            lastAudioSeq = null;
            primed = false;
        }
    }

    private final Object lock = new Object();
    private final PcmRingBuffer ringBuffer = new PcmRingBuffer(48_000, 2);
    private final LipSyncPolicy lipSync = new LipSyncPolicy();
    private final ArrayDeque<UdpMediaProtocol.AudioPayload> incomingPackets =
            new ArrayDeque<>(MAX_ENCODED_QUEUE_PACKETS);
    private double lastPacketArrivalMonoMs;
    private boolean running = true;
    private Thread playbackThread;

    public void updateVideoPipelineMode(boolean udpActive, double explicitDelayMs) {
        synchronized (lock) {
            lipSync.updateVideoPipelineDelay(udpActive, explicitDelayMs);
        }
    }

    public void recordVideoRender(long videoCaptureMs, double renderMonoMs) {
        synchronized (lock) {
            lipSync.recordVideoRender(videoCaptureMs, renderMonoMs);
        }
    }

    public void offer(UdpMediaProtocol.AudioPayload payload) {
        if (payload == null || payload.pcmBytes == null || payload.pcmBytes.length == 0) {
            return;
        }
        double arrivalMonoMs = monotonicNowMs();
        synchronized (lock) {
            if (!running) {
                return;
            }
            if (!ringBuffer.acceptPacketMetadata(
                    payload.audioSeq, payload.sampleRate, payload.channels)) {
                return;
            }
            lastPacketArrivalMonoMs = arrivalMonoMs;
            lipSync.recordAudioArrival(payload.captureTimestampMs, arrivalMonoMs);
            if (payload.formatFlags == UdpMediaProtocol.AudioPayload.FORMAT_S16LE_PCM
                    && incomingPackets.isEmpty()) {
                ringBuffer.writeBounded(payload.pcmBytes, 0, payload.pcmBytes.length);
                ringBuffer.applyLipSyncWatermark(
                        lipSync.targetBytes(payload.sampleRate, payload.channels),
                        lipSync.driftTrimThresholdBytes(payload.sampleRate, payload.channels));
            } else {
                if (incomingPackets.size() >= MAX_ENCODED_QUEUE_PACKETS) {
                    incomingPackets.pollFirst();
                }
                incomingPackets.addLast(payload);
            }
            if (playbackThread == null) {
                playbackThread = new Thread(this::playbackLoop, "DisplayWeave-Audio");
                playbackThread.setDaemon(true);
                playbackThread.start();
            }
            lock.notifyAll();
        }
    }

    public void stop() {
        Thread workerToJoin;
        synchronized (lock) {
            if (!running) {
                return;
            }
            running = false;
            incomingPackets.clear();
            ringBuffer.clear();
            lipSync.reset();
            workerToJoin = playbackThread;
            playbackThread = null;
            lock.notifyAll();
        }
        if (workerToJoin != null && workerToJoin != Thread.currentThread()) {
            workerToJoin.interrupt();
            try {
                workerToJoin.join(150);
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
    }

    @Override
    public void close() {
        stop();
    }

    private static final class OpusDecoderState {
        final MediaCodec codec;
        final int sampleRate;
        final int channels;
        int outputEncoding = AudioFormat.ENCODING_PCM_16BIT;
        long presentationTimeUs;
        byte[] decodeScratch = new byte[4096];

        OpusDecoderState(MediaCodec codec, int sampleRate, int channels) {
            this.codec = codec;
            this.sampleRate = sampleRate;
            this.channels = channels;
        }

        void close() {
            try {
                codec.stop();
            } catch (RuntimeException ignored) {
            }
            try {
                codec.release();
            } catch (RuntimeException ignored) {
            }
        }
    }

    private static OpusDecoderState createOpusDecoder(int sampleRate, int channels) {
        MediaCodec codec = null;
        try {
            codec = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_AUDIO_OPUS);
            MediaFormat format = MediaFormat.createAudioFormat(
                    MediaFormat.MIMETYPE_AUDIO_OPUS, sampleRate, channels);
            format.setByteBuffer("csd-0", ByteBuffer.wrap(buildOpusHead(sampleRate, channels)));
            format.setByteBuffer("csd-1", ByteBuffer.wrap(buildLittleEndianLongCsd(OPUS_PRE_SKIP_NS)));
            format.setByteBuffer("csd-2", ByteBuffer.wrap(buildLittleEndianLongCsd(OPUS_SEEK_PREROLL_NS)));
            format.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, UdpMediaProtocol.AudioPayload.MAX_PCM_BYTES);
            codec.configure(format, null, null, 0);
            codec.start();
            return new OpusDecoderState(codec, sampleRate, channels);
        } catch (Exception error) {
            if (codec != null) {
                try {
                    codec.release();
                } catch (RuntimeException ignored) {
                }
            }
            android.util.Log.w("DisplayWeave", "Opus MediaCodec init failed", error);
            return null;
        }
    }

    private void decodePacketIntoRingBuffer(
            UdpMediaProtocol.AudioPayload packet,
            OpusDecoderState decoder,
            MediaCodec.BufferInfo bufferInfo) {
        int inputIndex = decoder.codec.dequeueInputBuffer(2_000L);
        if (inputIndex >= 0) {
            ByteBuffer inputBuffer = decoder.codec.getInputBuffer(inputIndex);
            if (inputBuffer != null) {
                inputBuffer.clear();
                int copyLen = Math.min(packet.pcmBytes.length, inputBuffer.remaining());
                inputBuffer.put(packet.pcmBytes, 0, copyLen);
                decoder.codec.queueInputBuffer(
                        inputIndex, 0, copyLen, decoder.presentationTimeUs, 0);
                decoder.presentationTimeUs += 20_000L;
            } else {
                decoder.codec.queueInputBuffer(inputIndex, 0, 0, 0L, 0);
            }
        }
        for (int spin = 0; spin < 8; spin++) {
            int outIndex = decoder.codec.dequeueOutputBuffer(bufferInfo, 0L);
            if (outIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                break;
            }
            if (outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                MediaFormat outFormat = decoder.codec.getOutputFormat();
                if (outFormat != null && outFormat.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    decoder.outputEncoding = outFormat.getInteger(MediaFormat.KEY_PCM_ENCODING);
                }
                continue;
            }
            if (outIndex >= 0) {
                try {
                    ByteBuffer outBuf = decoder.codec.getOutputBuffer(outIndex);
                    if (outBuf != null && bufferInfo.size > 0) {
                        outBuf.position(bufferInfo.offset);
                        outBuf.limit(bufferInfo.offset + bufferInfo.size);
                        int pcm16Bytes = extractS16LeBytes(outBuf, bufferInfo.size, decoder);
                        if (pcm16Bytes > 0) {
                            synchronized (lock) {
                                if (running) {
                                    ringBuffer.writeBounded(decoder.decodeScratch, 0, pcm16Bytes);
                                    ringBuffer.applyLipSyncWatermark(
                                            lipSync.targetBytes(packet.sampleRate, packet.channels),
                                            lipSync.driftTrimThresholdBytes(
                                                    packet.sampleRate, packet.channels));
                                }
                            }
                        }
                    }
                } finally {
                    decoder.codec.releaseOutputBuffer(outIndex, false);
                }
            }
        }
    }

    private static int extractS16LeBytes(
            ByteBuffer outBuf, int byteCount, OpusDecoderState decoder) {
        if (decoder.outputEncoding == AudioFormat.ENCODING_PCM_FLOAT) {
            int sampleCount = byteCount / 4;
            int outBytes = sampleCount * 2;
            if (decoder.decodeScratch.length < outBytes) {
                decoder.decodeScratch = new byte[outBytes];
            }
            ByteBuffer floatView = outBuf.slice().order(ByteOrder.nativeOrder());
            ByteBuffer s16Out = ByteBuffer.wrap(decoder.decodeScratch, 0, outBytes)
                    .order(ByteOrder.LITTLE_ENDIAN);
            for (int i = 0; i < sampleCount; i++) {
                float sample = Math.max(-1.0f, Math.min(1.0f, floatView.getFloat()));
                short quantized = (short) Math.round(sample * 32767.0f);
                s16Out.putShort(quantized);
            }
            return outBytes;
        }
        if (decoder.decodeScratch.length < byteCount) {
            decoder.decodeScratch = new byte[byteCount];
        }
        outBuf.get(decoder.decodeScratch, 0, byteCount);
        return byteCount;
    }

    private void playbackLoop() {
        AudioTrack track = null;
        OpusDecoderState opusDecoder = null;
        boolean opusInitFailed = false;
        MediaCodec.BufferInfo bufferInfo = new MediaCodec.BufferInfo();
        int activeRate = 0;
        int activeChannels = 0;
        byte[] chunk = new byte[3840];
        try {
            while (true) {
                UdpMediaProtocol.AudioPayload pendingPacket = null;
                int bytesRead = 0;
                int targetRate;
                int targetChannels;
                synchronized (lock) {
                    while (running) {
                        if (!incomingPackets.isEmpty()) {
                            pendingPacket = incomingPackets.pollFirst();
                            break;
                        }
                        targetRate = ringBuffer.sampleRate();
                        targetChannels = ringBuffer.channels();
                        int targetBytes = lipSync.targetBytes(targetRate, targetChannels);
                        boolean flushTail = ringBuffer.availableBytes() > 0
                                && (monotonicNowMs() - lastPacketArrivalMonoMs) >= 45.0;
                        bytesRead = ringBuffer.drainPrimed(
                                chunk, chunk.length, targetBytes, flushTail);
                        if (bytesRead > 0) {
                            break;
                        }
                        try {
                            lock.wait(10L);
                        } catch (InterruptedException interrupted) {
                            if (!running) {
                                return;
                            }
                        }
                    }
                    if (!running) {
                        return;
                    }
                    targetRate = ringBuffer.sampleRate();
                    targetChannels = ringBuffer.channels();
                }

                if (pendingPacket != null) {
                    if (pendingPacket.formatFlags == UdpMediaProtocol.AudioPayload.FORMAT_S16LE_PCM) {
                        synchronized (lock) {
                            if (running) {
                                ringBuffer.writeBounded(
                                        pendingPacket.pcmBytes, 0, pendingPacket.pcmBytes.length);
                                ringBuffer.applyLipSyncWatermark(
                                        lipSync.targetBytes(
                                                pendingPacket.sampleRate, pendingPacket.channels),
                                        lipSync.driftTrimThresholdBytes(
                                                pendingPacket.sampleRate, pendingPacket.channels));
                            }
                        }
                    } else if (pendingPacket.formatFlags == UdpMediaProtocol.AudioPayload.FORMAT_OPUS
                            && !opusInitFailed) {
                        if (opusDecoder != null
                                && (opusDecoder.sampleRate != pendingPacket.sampleRate
                                        || opusDecoder.channels != pendingPacket.channels)) {
                            opusDecoder.close();
                            opusDecoder = null;
                        }
                        if (opusDecoder == null) {
                            opusDecoder = createOpusDecoder(
                                    pendingPacket.sampleRate, pendingPacket.channels);
                            if (opusDecoder == null) {
                                opusInitFailed = true;
                            }
                        }
                        if (opusDecoder != null) {
                            try {
                                decodePacketIntoRingBuffer(pendingPacket, opusDecoder, bufferInfo);
                            } catch (RuntimeException decodeError) {
                                android.util.Log.w(
                                        "DisplayWeave", "Opus MediaCodec decode failed", decodeError);
                                opusDecoder.close();
                                opusDecoder = null;
                                opusInitFailed = true;
                            }
                        }
                    }
                    continue;
                }

                if (bytesRead <= 0) {
                    continue;
                }
                if (track == null || activeRate != targetRate || activeChannels != targetChannels) {
                    releaseTrackQuietly(track);
                    track = createLowLatencyAudioTrack(targetRate, targetChannels);
                    activeRate = targetRate;
                    activeChannels = targetChannels;
                    if (track == null) {
                        continue;
                    }
                }
                try {
                    int written = track.write(chunk, 0, bytesRead, AudioTrack.WRITE_BLOCKING);
                    if (written < 0) {
                        releaseTrackQuietly(track);
                        track = null;
                    }
                } catch (RuntimeException error) {
                    releaseTrackQuietly(track);
                    track = null;
                }
            }
        } finally {
            if (opusDecoder != null) {
                opusDecoder.close();
            }
            releaseTrackQuietly(track);
        }
    }

    private static double monotonicNowMs() {
        try {
            long elapsed = android.os.SystemClock.elapsedRealtime();
            if (elapsed > 0L) {
                return (double) elapsed;
            }
        } catch (RuntimeException ignored) {
        }
        return System.nanoTime() / 1_000_000.0;
    }

    private static AudioTrack createLowLatencyAudioTrack(int sampleRate, int channels) {
        int channelMask = channels == 1
                ? AudioFormat.CHANNEL_OUT_MONO
                : AudioFormat.CHANNEL_OUT_STEREO;
        int minBuf = AudioTrack.getMinBufferSize(
                sampleRate, channelMask, AudioFormat.ENCODING_PCM_16BIT);
        if (minBuf <= 0) {
            minBuf = PcmRingBuffer.capacityBytesFor(sampleRate, channels);
        }
        int ringCapBytes = PcmRingBuffer.capacityBytesFor(sampleRate, channels);
        int bufferBytes = Math.max(Math.max(minBuf, ringCapBytes), channels * 2 * 256);

        AudioAttributes attributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                .build();
        AudioFormat format = new AudioFormat.Builder()
                .setSampleRate(sampleRate)
                .setChannelMask(channelMask)
                .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                .build();
        try {
            AudioTrack track = new AudioTrack.Builder()
                    .setAudioAttributes(attributes)
                    .setAudioFormat(format)
                    .setTransferMode(AudioTrack.MODE_STREAM)
                    .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                    .setBufferSizeInBytes(bufferBytes)
                    .build();
            track.play();
            return track;
        } catch (RuntimeException lowLatencyError) {
            try {
                AudioTrack fallback = new AudioTrack.Builder()
                        .setAudioAttributes(attributes)
                        .setAudioFormat(format)
                        .setTransferMode(AudioTrack.MODE_STREAM)
                        .setBufferSizeInBytes(bufferBytes)
                        .build();
                fallback.play();
                return fallback;
            } catch (RuntimeException failed) {
                android.util.Log.w("DisplayWeave", "AudioTrack init failed", failed);
                return null;
            }
        }
    }

    private static void releaseTrackQuietly(AudioTrack track) {
        if (track == null) {
            return;
        }
        try {
            if (track.getPlayState() == AudioTrack.PLAYSTATE_PLAYING) {
                track.pause();
                track.flush();
            }
            track.stop();
        } catch (RuntimeException ignored) {
        }
        try {
            track.release();
        } catch (RuntimeException ignored) {
        }
    }
}
