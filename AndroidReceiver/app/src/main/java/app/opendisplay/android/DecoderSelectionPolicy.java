package app.opendisplay.android;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

public final class DecoderSelectionPolicy {
    public static final class Candidate {
        public final String decoderName;
        public final boolean hardwareAccelerated;
        public final boolean softwareOnly;
        public final boolean vendor;
        public final boolean lowLatencySupported;

        public Candidate(String decoderName, boolean hardwareAccelerated,
                         boolean softwareOnly, boolean vendor,
                         boolean lowLatencySupported) {
            this.decoderName = decoderName;
            this.hardwareAccelerated = hardwareAccelerated;
            this.softwareOnly = softwareOnly;
            this.vendor = vendor;
            this.lowLatencySupported = lowLatencySupported;
        }
    }

    public static final class Attempt {
        public final String decoderName;
        public final boolean hardwareAccelerated;
        public final boolean softwareOnly;
        public final boolean vendor;
        public final boolean lowLatencySupported;
        public final boolean enableLowLatency;

        Attempt(Candidate candidate, boolean enableLowLatency) {
            decoderName = candidate.decoderName;
            hardwareAccelerated = candidate.hardwareAccelerated;
            softwareOnly = candidate.softwareOnly;
            vendor = candidate.vendor;
            lowLatencySupported = candidate.lowLatencySupported;
            this.enableLowLatency = enableLowLatency;
        }
    }

    private DecoderSelectionPolicy() {}

    public static List<Attempt> attempts(
            List<Candidate> candidates, DecoderLowLatencyMode mode) {
        List<Candidate> ordered = new ArrayList<>(candidates);
        ordered.sort(candidateComparator(mode));
        List<Attempt> result = new ArrayList<>();
        for (Candidate candidate : ordered) {
            if (mode.requestsLowLatency() && candidate.lowLatencySupported) {
                result.add(new Attempt(candidate, true));
            }
            result.add(new Attempt(candidate, false));
        }
        return result;
    }

    private static Comparator<Candidate> candidateComparator(
            DecoderLowLatencyMode mode) {
        return Comparator
                .comparingInt(DecoderSelectionPolicy::accelerationRank)
                .thenComparingInt(candidate ->
                        mode.requestsLowLatency() && candidate.lowLatencySupported ? 0 : 1);
    }

    private static int accelerationRank(Candidate candidate) {
        if (candidate.hardwareAccelerated) {
            return 0;
        }
        return candidate.softwareOnly ? 2 : 1;
    }
}
