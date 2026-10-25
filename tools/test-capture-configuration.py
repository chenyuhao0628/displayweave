#!/usr/bin/env python3
"""Execute the current recovery method with display/SCStream operations stubbed.

The method is extracted on every run, never maintained as a copied implementation.
Optional --source-ref demonstrates the regression against a historical source.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument("--source-ref")
args = parser.parse_args()
source = (subprocess.check_output(["git", "show", f"{args.source_ref}:Mac/MacSender.swift"], cwd=ROOT).decode()
          if args.source_ref else (ROOT / "Mac/MacSender.swift").read_text())
begin = source.index("    @MainActor private func recoverCapture(")
end = source.index("    private func scheduleReconfiguration(", begin)
method = source[begin:end].replace("private func recoverCapture", "func recoverCapture")
snapshot = (ROOT / "tools/audits/2026-10-26/RecoveryConfigurationProbe.swift").read_text()
fixture = snapshot[:snapshot.index("    @MainActor func recoverCapture(")]
fixture = fixture.replace("    var stopped = false", "    var appliedCaptureInfo: PhoneInfo?\n    var stopped = false")
fixture += method + "\n}\n" + r'''
@main struct ConfigurationRegression {
    @MainActor static func main() async throws {
        func hello(_ width: Int, _ height: Int) throws -> PhoneInfo {
            try JSONDecoder().decode(PhoneInfo.self, from: JSONSerialization.data(withJSONObject:
                ["pixelsWide": width, "pixelsHigh": height, "scale": 2, "device": "iPhone", "id": "test"]))
        }
        let original = try hello(1920, 1080), rotated = try hello(1080, 1920)
        let changed = RecoveryProbe()
        changed.appliedCaptureInfo = original
        let applied = await changed.recoverCapture(rotated)
        precondition(changed.rebuilds == 1 && changed.reattachedSize == nil,
                     "rotation while capture is nil must rebuild, not relabel old settings")
        precondition(applied?.sameDisplayConfiguration(as: rotated) == true)
        let unchanged = RecoveryProbe()
        unchanged.appliedCaptureInfo = original
        _ = await unchanged.recoverCapture(original)
        precondition(unchanged.rebuilds == 0 && unchanged.reattachedSize?.0 == 1920,
                     "matching hello should reattach without disrupting display arrangement")
        let locked = RecoveryProbe()
        locked.consoleCanCapture = false
        _ = await locked.recoverCapture(rotated)
        precondition(locked.rebuilds == 0 && locked.reattachedSize == nil)
        print("Capture configuration recovery PASS (current method, stubbed OS operations)")
    }
}
'''
files = ["Mac/DesktopResolution.swift", "Mac/FrameSizePolicy.swift", "Mac/RefreshRatePolicy.swift",
         "Mac/StreamEncodingPolicy.swift", "Mac/StreamSettings.swift", "Mac/DeviceCapabilities.swift",
         "Mac/Receiver/ReceiverWireProtocol.swift", "Mac/FrameDropPolicy.swift", "Mac/CaptureRecovery.swift",
         "Mac/DisplayUnitCoordinator.swift", "Mac/EncoderSessionFactory.swift"]
with tempfile.TemporaryDirectory(prefix="displayweave-configuration-") as tmp:
    path = Path(tmp)
    (path / "Fixture.swift").write_text(fixture)
    subprocess.run(["swiftc", *files, str(path / "Fixture.swift"), "-o", str(path / "test")], cwd=ROOT, check=True)
    subprocess.run([str(path / "test")], check=True)
