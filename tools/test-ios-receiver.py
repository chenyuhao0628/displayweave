#!/usr/bin/env python3
"""Opt-in loopback smoke test against a foreground iOS Simulator receiver.
Never captures a desktop. The receiver must listen on the supplied local port.
"""
import argparse
import json
import socket
import struct
import time
from pathlib import Path


def exact(peer, count):
    chunks = bytearray()
    while len(chunks) < count:
        chunk = peer.recv(count - len(chunks))
        if not chunk:
            raise EOFError("receiver closed")
        chunks.extend(chunk)
    return bytes(chunks)


def message(peer):
    length, = struct.unpack("!I", exact(peer, 4))
    assert 0 < length <= 1024 * 1024, "unbounded receiver control frame"
    return json.loads(exact(peer, length))


def connect(port, with_hello=False):
    peer = socket.create_connection(("127.0.0.1", port), timeout=2)
    peer.settimeout(2)
    hello = message(peer)
    assert hello.get("type") == "hello" and hello.get("device") in ("iPhone", "iPad"), "not an iOS receiver"
    assert "appleVideoV1" in hello.get("capabilities", []), "missing Apple video negotiation"
    assert 1 <= hello["displayMaxFrameRate"] <= 120
    return (peer, hello) if with_hello else peer


def send(peer, payload):
    if isinstance(payload, dict):
        payload = json.dumps(payload).encode()
    peer.sendall(struct.pack("!I", len(payload)) + payload)


def until_message(peer, kind):
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline:
        # The receiver schedules its heartbeat every 2s; allow scheduling jitter
        # without turning a healthy boundary into an exact-2s timeout failure.
        peer.settimeout(max(0.01, deadline - time.monotonic()))
        result = message(peer)
        if result.get("type") == kind:
            return result
    raise AssertionError(f"missing {kind}")


def closed(peer):
    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        try:
            if not peer.recv(4096):
                return True
        except ConnectionResetError:
            return True
        except socket.timeout:
            return False
    return False


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=9000)
    parser.add_argument("--video-fixtures", type=Path,
                        help="Synthetic frames exported by ReceiverVideoBitstreamSelfTest")
    args = parser.parse_args()
    # Simulator launch is asynchronous; wait only for the initial connection.
    deadline = time.monotonic() + 10
    while True:
        try:
            with connect(args.port):
                break
        except ConnectionRefusedError:
            if time.monotonic() >= deadline:
                raise
            time.sleep(0.1)
    for length in (0xFFFFFFFF, 0):
        with connect(args.port) as peer:
            peer.sendall(struct.pack("!I", length))
            assert closed(peer), f"invalid length {length} was not rejected before payload allocation"
    with connect(args.port) as old, connect(args.port) as fresh:
        assert closed(old), "replacement did not close old transport"
        ping = json.dumps({"type": "ping"}).encode()
        frame = struct.pack("!I", len(ping)) + ping
        fresh.sendall(frame[:2])
        fresh.sendall(frame[2:])
        assert message(fresh)["type"] == "ping", "replacement transport stopped sending liveness"
    with connect(args.port):
        pass
    base = {"type": "streamConfig", "codec": "h264", "width": 64, "height": 64, "fps": 60}
    for patch in ({"width": 3}, {"fps": 121}, {"codec": "unsupported"}):
        with connect(args.port) as peer:
            send(peer, base | patch)
            assert closed(peer), f"invalid video config accepted: {patch}"
    if args.video_fixtures:
        h264 = (args.video_fixtures / "synthetic.h264").read_bytes()
        peer, hello = connect(args.port, with_hello=True)
        with peer:
            send(peer, base | {"fps": hello["maxFps"]})
            send(peer, h264)
            until_message(peer, "ping")
            send(peer, base | {"codec": "hevc"})
            hevc = args.video_fixtures / "synthetic.hevc"
            if "hevc" in hello["supportedCodecs"] and hevc.exists():
                send(peer, hevc.read_bytes())
                until_message(peer, "ping")
            else:
                print("SKIP iOS HEVC presentation: simulator did not advertise hardware HEVC")
            send(peer, bytes([0, 0, 0, 1, 0x26, 0]))
            assert until_message(peer, "codecFailure")["codec"] == "hevc"
            send(peer, base)
            send(peer, h264)
            until_message(peer, "ping")
            send(peer, base | {"codec": "hevc"})
            assert closed(peer), "failed HEVC codec reaccepted during same connection"
    print("iOS loopback: framing, replacement, capability/config bounds and optional synthetic codec fallback PASS")


if __name__ == "__main__":
    main()
