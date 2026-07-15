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
  Mac/FrameSizePolicy.swift Mac/DeviceCapabilities.swift \
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
  Mac/Log.swift Mac/TestPatternWindow.swift \
  MacTests/TestPatternLifecycleSelfTest.swift
run_test TransportSelectionPolicySelfTest \
  "${settings[@]}" Mac/TransportSelectionPolicy.swift \
  MacTests/TransportSelectionPolicySelfTest.swift
run_test UpdateConfigurationSelfTest \
  -parse-as-library MacTests/UpdateConfigurationSelfTest.swift
run_test UpdateReleasePolicySelfTest \
  -parse-as-library MacTests/UpdateReleasePolicySelfTest.swift

echo "Swift standalone self-tests PASS (22 suites)"
