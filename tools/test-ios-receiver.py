#!/usr/bin/env python3
"""Opt-in loopback smoke test against a foreground iOS Simulator receiver.
Never captures a desktop. The receiver must listen on the supplied local port.
"""
import argparse
import json
import socket
import struct
import time


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


def connect(port):
    peer = socket.create_connection(("127.0.0.1", port), timeout=2)
    peer.settimeout(2)
    hello = message(peer)
    assert hello.get("type") == "hello" and hello.get("device") in ("iPhone", "iPad"), "not an iOS receiver"
    return peer


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
    print("iOS loopback: invalid lengths, old peer closure, fragmentation and replacement liveness PASS")


if __name__ == "__main__":
    main()
