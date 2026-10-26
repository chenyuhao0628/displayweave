#!/usr/bin/env bash
set -euo pipefail
audit_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$audit_dir/../../.." && pwd)"
cd "$repo_root"
probe_tmp="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-review-probes.XXXXXX")"
trap 'rm -rf "$probe_tmp"' EXIT
python3 "$audit_dir/verify-excerpts.py"
settings=(Mac/DesktopResolution.swift Mac/FrameSizePolicy.swift Mac/RefreshRatePolicy.swift Mac/StreamEncodingPolicy.swift Mac/StreamSettings.swift)
swiftc "${settings[@]}" Mac/FrameDropPolicy.swift Mac/GenerationWorkCounter.swift "$audit_dir/ReconnectKeyframeProbe.swift" -o "$probe_tmp/keyframe"
"$probe_tmp/keyframe"
swiftc "${settings[@]}" Mac/DeviceCapabilities.swift Mac/Receiver/ReceiverWireProtocol.swift Mac/FrameDropPolicy.swift Mac/CaptureRecovery.swift Mac/DisplayUnitCoordinator.swift Mac/EncoderSessionFactory.swift "$audit_dir/RecoveryConfigurationProbe.swift" -o "$probe_tmp/recovery"
"$probe_tmp/recovery"
swiftc "${settings[@]}" Mac/FrameDropPolicy.swift Mac/CaptureRecovery.swift Mac/DeviceCapabilities.swift Mac/Receiver/ReceiverWireProtocol.swift Mac/MacReceiverPolicy.swift Mac/EncoderSessionFactory.swift "$audit_dir/PersistentEncoderFailureProbe.swift" -o "$probe_tmp/failure"
"$probe_tmp/failure"
swiftc Mac/DisplayArrangement.swift "$audit_dir/ArrangementProbe.swift" -o "$probe_tmp/arrangement"
"$probe_tmp/arrangement"

swiftc "${settings[@]}" Mac/DeviceCapabilities.swift Mac/Receiver/ReceiverWireProtocol.swift Mac/MacReceiverPolicy.swift Mac/AdaptiveBitrateController.swift "$audit_dir/ParameterPolicyProbe.swift" -o "$probe_tmp/parameters"
"$probe_tmp/parameters"
swiftc -parse-as-library "$audit_dir/IOSBackpressureProbe.swift" -o "$probe_tmp/ios-backpressure"
"$probe_tmp/ios-backpressure"
android_src=AndroidReceiver/app/src/main/java/app/opendisplay/android
javac -d "$probe_tmp/java" "$android_src/TouchGestureCoordinator.java" "$android_src/FrameQueuePolicy.java" "$audit_dir/AndroidInteractionProbe.java"
java -cp "$probe_tmp/java" app.opendisplay.android.AndroidInteractionProbe
