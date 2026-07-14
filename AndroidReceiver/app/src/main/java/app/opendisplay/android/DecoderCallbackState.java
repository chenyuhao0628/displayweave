package app.opendisplay.android;

import java.util.ArrayDeque;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;

/** Owns callback-generation state without depending on Android codec classes. */
final class DecoderCallbackState {
    private final int telemetryLimit;
    private final ArrayDeque<Integer> availableInputs = new ArrayDeque<>();
    private final Set<Integer> availableInputSet = new HashSet<>();
    private final LinkedHashMap<Long, VideoFrameTelemetry> telemetry =
            new LinkedHashMap<>();
    private Object owner;
    private long generation;
    private long telemetryPeak;
    private long telemetryEvicted;

    DecoderCallbackState(int telemetryLimit) {
        this.telemetryLimit = Math.max(1, telemetryLimit);
    }

    long activate(Object owner) {
        generation++;
        this.owner = owner;
        clearOwnedData();
        return generation;
    }

    void invalidate() {
        generation++;
        owner = null;
        clearOwnedData();
    }

    boolean isActive(long generation, Object owner) {
        return owner != null && this.owner == owner && this.generation == generation;
    }

    boolean offerInput(int index) {
        if (!availableInputSet.add(index)) {
            return false;
        }
        availableInputs.addLast(index);
        return true;
    }

    Integer pollInput() {
        Integer index = availableInputs.pollFirst();
        if (index != null) {
            availableInputSet.remove(index);
        }
        return index;
    }

    void putTelemetry(long presentationTimeUs, VideoFrameTelemetry value) {
        telemetry.put(presentationTimeUs, value);
        telemetryPeak = Math.max(telemetryPeak, telemetry.size());
        while (telemetry.size() > telemetryLimit) {
            Iterator<Map.Entry<Long, VideoFrameTelemetry>> iterator =
                    telemetry.entrySet().iterator();
            if (!iterator.hasNext()) {
                break;
            }
            iterator.next();
            iterator.remove();
            telemetryEvicted++;
        }
    }

    VideoFrameTelemetry removeTelemetry(long presentationTimeUs) {
        return telemetry.remove(presentationTimeUs);
    }

    int telemetrySize() {
        return telemetry.size();
    }

    long telemetryPeak() {
        return telemetryPeak;
    }

    long telemetryEvicted() {
        return telemetryEvicted;
    }

    private void clearOwnedData() {
        availableInputs.clear();
        availableInputSet.clear();
        telemetry.clear();
    }
}
