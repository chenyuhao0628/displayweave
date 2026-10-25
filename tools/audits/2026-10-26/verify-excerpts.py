#!/usr/bin/env python3
"""Reject stale snapshot reproductions and verify the retained production excerpts."""
import hashlib
import json
from pathlib import Path
import subprocess

AUDIT = Path(__file__).resolve().parent
ROOT = AUDIT.parents[2]
manifest = json.loads((AUDIT / "source-snapshot.json").read_text())
for name, digest in manifest["files"].items():
    if hashlib.sha256((ROOT / name).read_bytes()).hexdigest() != digest:
        raise SystemExit("Source changed since audit; refresh excerpt before interpreting: " + name)


def method(text, name):
    # These retained methods have balanced braces in comments/string literals.
    # This is a snapshot verifier, not a general Swift parser.
    start = text.index("func " + name + "(")
    end = text.index("{", start) + 1
    depth = 1
    while depth:
        depth += (text[end] == "{") - (text[end] == "}")
        end += 1
    return text[start:end]


sender = (ROOT / "Mac/MacSender.swift").read_text()
for name, probe in [("recoverCapture", "RecoveryConfigurationProbe"),
                    ("handleEncodeFailure", "PersistentEncoderFailureProbe"),
                    ("scheduleDropReplay", "PersistentEncoderFailureProbe"),
                    ("armDropReplay", "PersistentEncoderFailureProbe")]:
    assert method(sender, name) == method((AUDIT / (probe + ".swift")).read_text(), name), name

probe = (AUDIT / "ReconnectKeyframeProbe.swift").read_text()
after = method(probe[probe.index("final class After"):], "handleEncodedFrame").rsplit("}", 1)[0].rstrip()
assert method(sender, "handleEncodedFrame").startswith(after)
baseline = subprocess.check_output(["git", "show", "39f97a5:Mac/MacSender.swift"], cwd=ROOT, text=True)
before = method(probe, "handleEncodedFrame").replace(
    '        case .stale: preconditionFailure("old policy has no stale disposition")\n', ""
).rsplit("}", 1)[0].rstrip()
assert method(baseline, "handleEncodedFrame").startswith(before)

ios = (AUDIT / "IOSBackpressureProbe.swift").read_text()
start = ios.index("        if displayLayer.status == .failed")
end = ios.index("        admitted += 1", start)
assert ios[start:end] in (ROOT / "iOS/PhoneReceiver.swift").read_text()
print("Production hashes and retained excerpts match audit " + manifest["revision"])
