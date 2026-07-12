package app.opendisplay.android;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class MetricDistribution {
    public static final long MISSING_MS = -1L;

    private final int capacity;
    private final ArrayDeque<Long> values = new ArrayDeque<>();

    public MetricDistribution(int capacity) {
        if (capacity <= 0) {
            throw new IllegalArgumentException("capacity must be positive");
        }
        this.capacity = capacity;
    }

    public void add(long value) {
        if (value < 0) {
            return;
        }
        if (values.size() == capacity) {
            values.removeFirst();
        }
        values.addLast(value);
    }

    public int size() {
        return values.size();
    }

    public long latest() {
        Long value = values.peekLast();
        return value == null ? MISSING_MS : value;
    }

    public long p50() {
        return percentile(0.50);
    }

    public long p95() {
        return percentile(0.95);
    }

    public long p99() {
        return percentile(0.99);
    }

    private long percentile(double fraction) {
        if (values.isEmpty()) {
            return MISSING_MS;
        }
        List<Long> sorted = new ArrayList<>(values);
        Collections.sort(sorted);
        int index = Math.max(0, Math.min(sorted.size() - 1,
                (int) Math.ceil(fraction * sorted.size()) - 1));
        return sorted.get(index);
    }
}
