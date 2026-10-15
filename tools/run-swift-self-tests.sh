#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

temporary="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-swift-tests.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
cache="$temporary/module-cache"
mkdir -p "$cache"

run_test() {
  local name="$1"
  shift
  swiftc -module-cache-path "$cache" "$@" -o "$temporary/$name"
  "$temporary/$name"
}

settings=(
  Mac/FrameSizePolicy.swift
  Mac/RefreshRatePolicy.swift
  Mac/StreamEncodingPolicy.swift
  Mac/StreamSettings.swift
)

run_test AdaptiveBitrateControllerSelfTest \
  "${settings[@]}" Mac/AdaptiveBitrateController.swift \
  MacTests/AdaptiveBitrateControllerSelfTest.swift
run_test AndroidAdbSelfTest \
  Mac/AndroidAdb.swift MacTests/AndroidAdbSelfTest.swift
run_test AndroidAdbForwardSelfTest \
  Mac/AndroidAdb.swift Mac/AndroidAdbForward.swift \
  MacTests/AndroidAdbForwardSelfTest.swift
run_test ApplicationIdentityPolicySelfTest \
  Mac/ApplicationIdentityPolicy.swift \
  MacTests/ApplicationIdentityPolicySelfTest.swift
run_test BenchmarkIntegrationPolicySelfTest \
  Mac/BenchmarkSample.swift Mac/BenchmarkIntegrationPolicy.swift \
  MacTests/BenchmarkIntegrationPolicySelfTest.swift
run_test BenchmarkSampleSelfTest \
  Mac/BenchmarkSample.swift MacTests/BenchmarkSampleSelfTest.swift
run_test BenchmarkRecorderSelfTest \
  Mac/BenchmarkSample.swift Mac/BenchmarkRecorder.swift \
  MacTests/BenchmarkRecorderSelfTest.swift
run_test BinaryFrameHeaderV2SelfTest \
  "${settings[@]}" Mac/BinaryFrameHeaderV2.swift \
  MacTests/BinaryFrameHeaderV2SelfTest.swift
run_test DeviceCapabilitiesSelfTest \
  Mac/FrameSizePolicy.swift Mac/DeviceCapabilities.swift Mac/Receiver/ReceiverWireProtocol.swift \
  MacTests/DeviceCapabilitiesSelfTest.swift
run_test KeyframePolicySelfTest \
  "${settings[@]}" Mac/KeyframePolicy.swift MacTests/KeyframePolicySelfTest.swift
run_test KeyframeRequestPolicySelfTest \
  Mac/FrameDropPolicy.swift MacTests/KeyframeRequestPolicySelfTest.swift
run_test MacSenderTestPatternContractSelfTest \
  -parse-as-library MacTests/MacSenderTestPatternContractSelfTest.swift
run_test MetalRenderPassOrderingSelfTest \
  -parse-as-library MacTests/MetalRenderPassOrderingSelfTest.swift
run_test ReceiverSceneLifecyclePolicySelfTest \
  iOS/ReceiverSceneLifecyclePolicy.swift \
  MacTests/ReceiverSceneLifecyclePolicySelfTest.swift
run_test RefreshRatePolicySelfTest \
  Mac/RefreshRatePolicy.swift MacTests/RefreshRatePolicySelfTest.swift
run_test SendQueuePolicySelfTest \
  "${settings[@]}" Mac/GenerationWorkCounter.swift Mac/SendQueuePolicy.swift \
  Mac/FrameDropPolicy.swift MacTests/SendQueuePolicySelfTest.swift
run_test StreamEncodingPolicySelfTest \
  "${settings[@]}" MacTests/StreamEncodingPolicySelfTest.swift
run_test StreamSettingsSelfTest \
  "${settings[@]}" MacTests/StreamSettingsSelfTest.swift
run_test TestPatternLifecycleSelfTest \
  -DDEBUG \
  Shared/BoundedLogWriter.swift Mac/Log.swift Mac/TestPatternWindow.swift \
  MacTests/TestPatternLifecycleSelfTest.swift
run_test TransportSelectionPolicySelfTest \
  "${settings[@]}" Mac/TransportSelectionPolicy.swift \
  MacTests/TransportSelectionPolicySelfTest.swift
run_test UpdateConfigurationSelfTest \
  -parse-as-library MacTests/UpdateConfigurationSelfTest.swift
run_test UpdateReleasePolicySelfTest \
  -parse-as-library MacTests/UpdateReleasePolicySelfTest.swift


run_test MacReceiverPolicySelfTest \
  "${settings[@]}" Mac/DeviceCapabilities.swift Mac/MacReceiverPolicy.swift \
  Mac/Receiver/ReceiverWireProtocol.swift Shared/ReceiverFrameDecoder.swift \
  MacTests/MacReceiverPolicySelfTest.swift

run_test MacReceiverNetworkSelfTest \
  Mac/EncoderHardwareCapabilities.swift Mac/Receiver/ReceiverWireProtocol.swift Shared/ReceiverFrameDecoder.swift \
  Shared/ReceiverCursorImage.swift Mac/Receiver/ReceiverVideoBitstream.swift Mac/Receiver/StreamReceiver.swift MacTests/ReceiverTestSupport.swift MacTests/MacReceiverNetworkSelfTest.swift

run_test MacRoleControllerSelfTest \
  Mac/MacRoleController.swift MacTests/MacRoleControllerSelfTest.swift

run_test UsbmuxCancellationSelfTest \
  Shared/BoundedLogWriter.swift Mac/Usbmux.swift Mac/Log.swift MacTests/UsbmuxCancellationSelfTest.swift

run_test SessionLifetimeSelfTest \
  Mac/SessionLifetime.swift MacTests/SessionLifetimeSelfTest.swift

run_test BoundedLogWriterSelfTest \
  Shared/BoundedLogWriter.swift MacTests/BoundedLogWriterSelfTest.swift

run_test TouchPressPolicySelfTest \
  iOS/TouchPressPolicy.swift MacTests/TouchPressPolicySelfTest.swift

run_test InputValidationPolicySelfTest \
  Mac/InputValidationPolicy.swift MacTests/InputValidationPolicySelfTest.swift

run_test PermissionMonitorSelfTest \
  Mac/PermissionMonitor.swift MacTests/PermissionMonitorSelfTest.swift

run_test ReceiverCursorImageSelfTest \
  Shared/ReceiverCursorImage.swift MacTests/ReceiverCursorImageSelfTest.swift

run_test ReceiverVideoBitstreamSelfTest \
  Mac/EncoderHardwareCapabilities.swift Mac/Receiver/ReceiverVideoBitstream.swift MacTests/ReceiverTestSupport.swift \
  MacTests/ReceiverVideoBitstreamSelfTest.swift

run_test DirectCableSelfTest \
  Mac/DirectCable.swift MacTests/DirectCableSelfTest.swift

echo "Swift standalone self-tests PASS (34 suites)"
