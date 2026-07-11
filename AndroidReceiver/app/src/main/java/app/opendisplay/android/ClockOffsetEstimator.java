package app.opendisplay.android;

import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class ClockOffsetEstimator {
    public static final long MISSING_MS = -1L;

    public enum State {
        ESTIMATING,
        STABLE
    }

    private static final double MAX_RTT_MS = 250.0;
    private static final int MIN_STABLE_SAMPLES = 3;

    private final int capacity;
    private final ArrayDeque<Sample> samples = new ArrayDeque<>();

    public ClockOffsetEstimator(int capacity) {
        if (capacity < MIN_STABLE_SAMPLES) {
            throw new IllegalArgumentException("capacity must be at least three");
        }
        this.capacity = capacity;
    }

    public boolean addSample(double receiverSendMs, double macReceiveMs,
                             double macSendMs, double receiverReceiveMs) {
        double rttMs = (receiverReceiveMs - receiverSendMs) - (macSendMs - macReceiveMs);
        if (!Double.isFinite(rttMs) || rttMs < 0 || rttMs > MAX_RTT_MS) {
            return false;
        }
        double offsetMs = ((macReceiveMs - receiverSendMs)
                + (macSendMs - receiverReceiveMs)) / 2.0;
        if (!Double.isFinite(offsetMs)) {
            return false;
        }
        if (samples.size() == capacity) {
            samples.removeFirst();
        }
        samples.addLast(new Sample(rttMs, offsetMs));
        return true;
    }

    public int sampleCount() {
        return samples.size();
    }

    public State state() {
        return samples.size() >= MIN_STABLE_SAMPLES ? State.STABLE : State.ESTIMATING;
    }

    public long offsetMs() {
        List<Sample> selected = selectedSamples();
        if (state() != State.STABLE || selected.isEmpty()) {
            return MISSING_MS;
        }
        selected.sort(Comparator.comparingDouble(sample -> sample.offsetMs));
        int upperIndex = selected.size() / 2;
        double median = selected.get(upperIndex).offsetMs;
        if (selected.size() % 2 == 0) {
            median = (selected.get(upperIndex - 1).offsetMs + median) / 2.0;
        }
        return Math.round(median);
    }

    public long confidenceMs() {
        List<Sample> selected = selectedSamples();
        if (state() != State.STABLE || selected.isEmpty()) {
            return MISSING_MS;
        }
        double minimum = selected.get(0).rttMs;
        double maximum = minimum;
        for (Sample sample : selected) {
            minimum = Math.min(minimum, sample.rttMs);
            maximum = Math.max(maximum, sample.rttMs);
        }
        return Math.round((maximum - minimum) / 2.0);
    }

    private List<Sample> selectedSamples() {
        List<Sample> ordered = new ArrayList<>(samples);
        ordered.sort(Comparator.comparingDouble(sample -> sample.rttMs));
        int selectedCount = (ordered.size() + 1) / 2;
        return new ArrayList<>(ordered.subList(0, selectedCount));
    }

    private static final class Sample {
        final double rttMs;
        final double offsetMs;

        Sample(double rttMs, double offsetMs) {
            this.rttMs = rttMs;
            this.offsetMs = offsetMs;
        }
    }
}
