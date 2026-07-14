package app.opendisplay.android;

/** Owns negotiated protocol identity for one current transport generation. */
final class ReceiverProtocolSession {
    private long generation;
    private long sessionEpoch;
    private long configVersion;
    private long lastFrameSequence;
    private boolean negotiatedV2;
    private boolean configured;

    synchronized void onConnected(long generation) {
        this.generation = generation;
        sessionEpoch = 0;
        configVersion = 0;
        lastFrameSequence = 0;
        negotiatedV2 = false;
        configured = false;
    }

    synchronized boolean acceptStreamConfig(
            long generation, int protocolVersion, long sessionEpoch, long configVersion) {
        if (generation <= 0 || generation != this.generation) {
            return false;
        }
        boolean requestedV2 = protocolVersion >= 2;
        if (configured && negotiatedV2 && !requestedV2) {
            return false;
        }
        if (requestedV2 && (sessionEpoch <= 0 || configVersion <= 0)) {
            return false;
        }
        if (requestedV2 && configured) {
            if (sessionEpoch < this.sessionEpoch
                    || (sessionEpoch == this.sessionEpoch && configVersion <= this.configVersion)) {
                return false;
            }
        }
        negotiatedV2 = requestedV2;
        this.sessionEpoch = requestedV2 ? sessionEpoch : 0;
        this.configVersion = requestedV2 ? configVersion : 0;
        lastFrameSequence = 0;
        configured = true;
        return true;
    }

    synchronized boolean acceptFrame(long generation, VideoFrameTelemetry telemetry) {
        if (!configured || generation != this.generation || telemetry == null) {
            return false;
        }
        if (!negotiatedV2) {
            return true;
        }
        if (telemetry.sessionEpoch != sessionEpoch
                || telemetry.configVersion != configVersion
                || telemetry.frameSequence <= lastFrameSequence) {
            return false;
        }
        lastFrameSequence = telemetry.frameSequence;
        return true;
    }

    synchronized boolean isNegotiatedV2() {
        return negotiatedV2;
    }

    synchronized long sessionEpoch() {
        return sessionEpoch;
    }

    synchronized long configVersion() {
        return configVersion;
    }

    synchronized boolean matchesCurrentFrame(VideoFrameTelemetry telemetry) {
        if (!negotiatedV2) {
            return configured;
        }
        return telemetry != null
                && telemetry.sessionEpoch == sessionEpoch
                && telemetry.configVersion == configVersion
                && telemetry.frameSequence > 0;
    }

    synchronized boolean matchesIdentity(long sessionEpoch, long configVersion) {
        if (!configured) {
            return false;
        }
        if (!negotiatedV2) {
            return sessionEpoch == 0 && configVersion == 0;
        }
        return sessionEpoch == this.sessionEpoch && configVersion == this.configVersion;
    }
}
