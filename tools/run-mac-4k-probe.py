#!/usr/bin/env python3
"""Bounded, offscreen VideoToolbox probe; never captures or changes displays."""
import pathlib
import platform
import argparse
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCES = [
    "Mac/DesktopResolution.swift", "Mac/FrameSizePolicy.swift", "Mac/RefreshRatePolicy.swift",
    "Mac/StreamEncodingPolicy.swift", "Mac/StreamSettings.swift", "Mac/SendQueuePolicy.swift",
    "Mac/FrameDropPolicy.swift", "MacTests/Mac4KEncoderProbe.swift",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bitrate-mbps', type=int, choices=[50, 80, 100],
                        help='Override the default 49,766,400 bps target for this probe only')
    args = parser.parse_args()
    bitrate = args.bitrate_mbps * 1_000_000 if args.bitrate_mbps else 49_766_400
    print(f"Host: {platform.machine()}, macOS {platform.mac_ver()[0]}; synthetic encoding only", flush=True)
    print(f"Target bitrate: {bitrate} bps", flush=True)
    with tempfile.TemporaryDirectory(prefix="displayweave-4k-probe-") as temporary:
        binary = str(pathlib.Path(temporary) / "4KEncoderProbe")
        subprocess.run(["xcrun", "swiftc", "-O", *SOURCES, "-o", binary],
                       cwd=ROOT, check=True, timeout=90)
        subprocess.run([binary, str(bitrate)], cwd=ROOT, check=True, timeout=20)


if __name__ == "__main__":
    main()
