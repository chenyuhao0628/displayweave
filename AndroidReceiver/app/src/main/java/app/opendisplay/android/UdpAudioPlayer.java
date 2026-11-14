package app.opendisplay.android;

import android.media.AudioAttributes;
import android.media.AudioFormat;
import android.media.AudioTrack;

import app.opendisplay.android.protocol.UdpMediaProtocol;

/**
 * Low-latency PCM playback wrapper around {@link AudioTrack} for {@code udpAudioV1}.
 * Uses a bounded 60ms S16LE ring buffer drained by a dedicated playback worker thread
 * so network receive threads never block on audio hardware writes.
 */
public final class UdpAudioPlayer implements AutoCloseable {
    public static final int MAX_RING_BUFFER_MS = 60;

    /** Pure-Java bounded S16LE ring buffer with frame-aligned overflow trimming (60ms cap). */
    static final class PcmRingBuffer {
        private byte[] buffer;
        private int sampleRate;
        private int channels;
        private int frameBytes;
        private int readPos;
        private int size;
        private Long lastAudioSeq;
        private long droppedOverflowBytes;

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

        boolean offerPacket(UdpMediaProtocol.AudioPayload packet) {
            if (packet == null || packet.pcmBytes == null || packet.pcmBytes.length == 0) {
                return false;
            }
            if (packet.sampleRate != sampleRate || packet.channels != channels) {
                reconfigure(packet.sampleRate, packet.channels);
            } else if (lastAudioSeq != null
                    && UdpMediaProtocol.compareFrameId(packet.audioSeq, lastAudioSeq) <= 0) {
                return false;
            }
            lastAudioSeq = packet.audioSeq;
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
            return toRead;
        }

        void clear() {
            readPos = 0;
            size = 0;
            lastAudioSeq = null;
        }
    }

    private final Object lock = new Object();
    private final PcmRingBuffer ringBuffer = new PcmRingBuffer(48_000, 2);
    private boolean running = true;
    private Thread playbackThread;

    public void offer(UdpMediaProtocol.AudioPayload payload) {
        if (payload == null) {
            return;
        }
        synchronized (lock) {
            if (!running) {
                return;
            }
            if (!ringBuffer.offerPacket(payload)) {
                return;
            }
            if (playbackThread == null) {
                playbackThread = new Thread(this::playbackLoop, "DisplayWeave-UDP-Audio");
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
            ringBuffer.clear();
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

    private void playbackLoop() {
        AudioTrack track = null;
        int activeRate = 0;
        int activeChannels = 0;
        byte[] chunk = new byte[2304];
        try {
            while (true) {
                int bytesRead;
                int targetRate;
                int targetChannels;
                synchronized (lock) {
                    while (running && ringBuffer.availableBytes() == 0) {
                        try {
                            lock.wait(20L);
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
                    bytesRead = ringBuffer.drain(chunk, chunk.length);
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
            releaseTrackQuietly(track);
        }
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
        int sixtyMsBytes = PcmRingBuffer.capacityBytesFor(sampleRate, channels);
        int bufferBytes = Math.max(Math.max(minBuf, sixtyMsBytes), channels * 2 * 256);

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
