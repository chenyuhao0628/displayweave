package app.opendisplay.android;

import java.util.EnumMap;
import java.util.LinkedHashMap;
import java.util.Map;

public final class AndroidDropTracker {
    public static final class Context {
        public final long generation;
        public final long sessionEpoch;
        public final long configVersion;
        public final long frameSequence;
        public final String codec;
        public final String transport;

        public Context(long generation, long sessionEpoch, long configVersion,
                       long frameSequence, String codec, String transport) {
            this.generation = generation;
            this.sessionEpoch = sessionEpoch;
            this.configVersion = configVersion;
            this.frameSequence = frameSequence;
            this.codec = safe(codec);
            this.transport = safe(transport);
        }
    }

    public static final class Event {
        public final String reason;
        public final long countWindow;
        public final long countTotal;
        public final long generation;
        public final long sessionEpoch;
        public final long configVersion;
        public final long frameSequence;
        public final String codec;
        public final String transport;

        Event(AndroidDropReason reason, long countWindow, long countTotal,
              Context context) {
            this.reason = reason.key;
            this.countWindow = countWindow;
            this.countTotal = countTotal;
            generation = context.generation;
            sessionEpoch = context.sessionEpoch;
            configVersion = context.configVersion;
            frameSequence = context.frameSequence;
            codec = context.codec;
            transport = context.transport;
        }

        public Map<String, Object> asMap() {
            Map<String, Object> values = new LinkedHashMap<>();
            values.put("reason", reason);
            values.put("countWindow", countWindow);
            values.put("countTotal", countTotal);
            values.put("generation", generation);
            values.put("sessionEpoch", sessionEpoch);
            values.put("configVersion", configVersion);
            values.put("frameSequence", frameSequence);
            values.put("codec", codec);
            values.put("transport", transport);
            return values;
        }
    }

    public static final class Snapshot {
        private final EnumMap<AndroidDropReason, Long> windowCounts;
        private final EnumMap<AndroidDropReason, Long> totalCounts;
        public final long windowDropCount;
        public final long totalDropCount;
        public final long congestionRelevantWindowCount;
        public final Event lastEvent;

        Snapshot(EnumMap<AndroidDropReason, Long> windowCounts,
                 EnumMap<AndroidDropReason, Long> totalCounts,
                 long windowDropCount, long totalDropCount,
                 long congestionRelevantWindowCount, Event lastEvent) {
            this.windowCounts = windowCounts;
            this.totalCounts = totalCounts;
            this.windowDropCount = windowDropCount;
            this.totalDropCount = totalDropCount;
            this.congestionRelevantWindowCount = congestionRelevantWindowCount;
            this.lastEvent = lastEvent;
        }

        public long windowCount(AndroidDropReason reason) {
            return value(windowCounts, reason);
        }

        public long totalCount(AndroidDropReason reason) {
            return value(totalCounts, reason);
        }

        public Map<String, Object> windowCountsMap() {
            return asMap(windowCounts);
        }

        public Map<String, Object> totalCountsMap() {
            return asMap(totalCounts);
        }

        private static Map<String, Object> asMap(
                EnumMap<AndroidDropReason, Long> counts) {
            Map<String, Object> values = new LinkedHashMap<>();
            for (AndroidDropReason reason : AndroidDropReason.values()) {
                long count = value(counts, reason);
                if (count > 0) {
                    values.put(reason.key, count);
                }
            }
            return values;
        }
    }

    private final EnumMap<AndroidDropReason, Long> windowCounts =
            new EnumMap<>(AndroidDropReason.class);
    private final EnumMap<AndroidDropReason, Long> totalCounts =
            new EnumMap<>(AndroidDropReason.class);
    private long windowDropCount;
    private long totalDropCount;
    private long congestionRelevantWindowCount;
    private Event lastEvent;

    public synchronized void record(AndroidDropReason reason, Context context) {
        if (reason == null || context == null) {
            return;
        }
        long window = value(windowCounts, reason) + 1;
        long total = value(totalCounts, reason) + 1;
        windowCounts.put(reason, window);
        totalCounts.put(reason, total);
        windowDropCount++;
        totalDropCount++;
        if (reason.congestionRelevant) {
            congestionRelevantWindowCount++;
        }
        lastEvent = new Event(reason, window, total, context);
    }

    public synchronized Snapshot snapshotAndResetWindow() {
        Snapshot snapshot = new Snapshot(
                copy(windowCounts), copy(totalCounts), windowDropCount,
                totalDropCount, congestionRelevantWindowCount, lastEvent);
        windowCounts.clear();
        windowDropCount = 0;
        congestionRelevantWindowCount = 0;
        lastEvent = null;
        return snapshot;
    }

    private static EnumMap<AndroidDropReason, Long> copy(
            EnumMap<AndroidDropReason, Long> source) {
        return new EnumMap<>(source);
    }

    private static long value(Map<AndroidDropReason, Long> counts,
                              AndroidDropReason reason) {
        Long value = counts.get(reason);
        return value == null ? 0 : value;
    }

    private static String safe(String value) {
        return value == null ? "" : value;
    }
}
