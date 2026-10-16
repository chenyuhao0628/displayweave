#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/displayweave-window-test.XXXXXX")"
trap 'rm -rf "$temporary"' EXIT
swiftc Mac/Receiver/ReceiverWireProtocol.swift Shared/ReceiverFrameDecoder.swift \
  Shared/ReceiverCursorImage.swift Shared/ReceiverVideoBitstream.swift Shared/AppleVideoPolicy.swift Mac/Receiver/StreamReceiver.swift Mac/Receiver/ReceiverVideoView.swift \
  Mac/Receiver/MacReceiverController.swift MacTests/ReceiverTestSupport.swift \
  MacTests/MacReceiverWindowSelfTest.swift -o "$temporary/ReceiverWindowTest"
"$temporary/ReceiverWindowTest"
swiftc -import-objc-header Mac/OpenSidecarMac-Bridging-Header.h \
  Mac/VirtualDisplay.swift Mac/RefreshRatePolicy.swift Shared/BoundedLogWriter.swift Mac/Log.swift \
  MacTests/MacVirtualDisplaySelfTest.swift -o "$temporary/VirtualDisplayTest"
"$temporary/VirtualDisplayTest"
