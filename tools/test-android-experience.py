#!/usr/bin/env python3
"""Extend the existing disposable Android fixture with synthetic-video UX checks.

No installed app/device is modified. Uses the fixture's owned AVD, application,
forward and cleanup. Requires ffmpeg plus its documented Android prerequisites.
Pass --screenshots <ignored-local-directory>; image content is synthetic.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
fixture = ROOT / "tools/test-secure-android-receiver.py"
source = fixture.read_text()
marker = '            device("shell", "input", "keyevent", "3")\n            def stopped():'
assert source.count(marker) == 1, "Fixture changed; review insertion point"
extra = r'''
            # All changes below target only this fixture's disposable emulator.
            import threading
            tap("连接客户端：DisplayWeave 加密")
            tap("OpenDisplay 兼容（未加密）")
            tap("启用明文兼容")
            wait_until(legacy_hello, "UX fixture legacy listener", 10)
            tap("完成")
            # A square in a 16:9 synthetic video must remain square on the panel.
            ppm = folder / "aspect.ppm"
            pixels = bytearray()
            for py in range(360):
                for px in range(640):
                    pixels.extend(b"\x00\x00\x00" if 260 <= px < 380 and 120 <= py < 240
                                  else b"\xff\xff\xff")
            ppm.write_bytes(b"P6\n640 360\n255\n" + pixels)
            video = folder / "aspect.h264"
            run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-loop", "1", "-i", ppm,
                 "-r", "30", "-frames:v", "90", "-c:v", "libx264", "-preset", "ultrafast",
                 "-tune", "zerolatency", "-pix_fmt", "yuv420p", "-x264-params",
                 "aud=1:keyint=30:repeat-headers=1", "-f", "h264", video])
            encoded = video.read_bytes()
            auds = [match.start() for match in re.finditer(b"\x00\x00\x00\x01\x09", encoded)]
            assert len(auds) == 90
            packets = [encoded[lo:hi] for lo, hi in zip(auds, auds[1:] + [len(encoded)])]
            ux_peer = socket.create_connection(("127.0.0.1", int(forwarded)), timeout=5)
            ux_peer.settimeout(5)
            ux_stop = threading.Event()
            ux_errors = []
            ux_controls = []
            def send_packet(payload):
                ux_peer.sendall(struct.pack(">I", len(payload)) + payload)
            def read_messages():
                try:
                    while not ux_stop.is_set():
                        header = bytearray()
                        while len(header) < 4:
                            data = ux_peer.recv(4 - len(header))
                            if not data: return
                            header.extend(data)
                        remaining = struct.unpack(">I", header)[0]
                        if not 0 < remaining <= 65536: raise ValueError("invalid fixture control length")
                        payload = bytearray()
                        while remaining:
                            data = ux_peer.recv(remaining)
                            if not data: return
                            payload.extend(data)
                            remaining -= len(data)
                        message = json.loads(payload)
                        if message.get("type") in ("touch", "scroll"):
                            ux_controls.append((time.monotonic(), message))
                except OSError:
                    pass
            def stream_video():
                try:
                    send_packet(json.dumps({"type":"streamConfig", "codec":"h264", "fps":30,
                                           "width":640, "height":360, "bitrate":1000000}).encode())
                    frame_number = 0
                    while not ux_stop.wait(1 / 30):
                        send_packet(packets[frame_number % len(packets)])
                        frame_number += 1
                        if frame_number % 30 == 0:
                            send_packet(json.dumps({"type":"ping", "t":time.time()*1000,
                                                    "requestedFps":30}).encode())
                except OSError as error:
                    if not ux_stop.is_set(): ux_errors.append(type(error).__name__)
            reader = threading.Thread(target=read_messages, daemon=True)
            sender = threading.Thread(target=stream_video, daemon=True)
            reader.start(); sender.start()
            try:
                def concise_text():
                    return next((n.get("text", "") for n in tree().iter("node")
                                 if n.get("text", "").startswith("正在接收 · 640×360")), "")
                before = wait_until(concise_text, "aspect-correct video and concise default status", 25)
                assert "FPS" not in before, before
                if args.screenshots:
                    image = args.screenshots / "android-synthetic-aspect.png"
                    image.write_bytes(device("exec-out", "screencap", "-p"))
                    # Find the dark synthetic square in the central video region.
                    # Use system Swift/ImageIO so no extra Python packages are needed.
                    probe = folder / "Square.swift"
                    probe.write_text(r"""
import Foundation
import AppKit
let image = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))!
var xs: [Int] = [], ys: [Int] = []
for y in (image.pixelsHigh * 2 / 5)..<(image.pixelsHigh * 3 / 5) {
    for x in (image.pixelsWide / 3)..<(image.pixelsWide * 2 / 3) {
        let c = image.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
        if c.redComponent < 0.1 && c.greenComponent < 0.1 && c.blueComponent < 0.1 { xs.append(x); ys.append(y) }
    }
}
precondition(!xs.isEmpty)
let w = xs.max()! - xs.min()! + 1, h = ys.max()! - ys.min()! + 1
precondition(abs(w - h) <= 3, "synthetic square stretched: \(w)x\(h)")
print("Synthetic square retains aspect: \(w)x\(h)")
""")
                    run(["swift", probe, image])
                tap("设置")
                assert any(n.get("text") == "显示延迟和帧率" and n.get("checked") == "false" for n in tree().iter("node")), "metrics must default off"
                tap("显示延迟和帧率")
                tap("完成")
                def detailed_overlay():
                    return any("目标 30 FPS" in n.get("text", "") for n in tree().iter("node"))
                wait_until(detailed_overlay, "metrics enabled immediately", 5)
                tap("设置")
                tap("显示延迟和帧率")
                tap("完成")
                assert not detailed_overlay(), "metrics-off must immediately clear old metrics"
                if args.screenshots:
                    (args.screenshots / "android-metrics-disabled.png").write_bytes(device("exec-out", "screencap", "-p"))
                print("Android experience: concise default, aspect-correct video, metrics on/off PASS", flush=True)
                video_node = next(n for n in tree().iter("node") if n.get("content-desc", "").startswith("远程画面"))
                left, top, right, bottom = map(int, re.findall(r"\d+", video_node.get("bounds")))
                cx, cy = (left + right) // 2, (top + bottom) // 2
                ux_controls.clear()
                device("shell", "input", "tap", str(cx), str(top - 60))
                time.sleep(.3)
                assert not ux_controls, "letterbox tap leaked into remote input"
                device("shell", "input", "tap", str(cx), str(cy))
                wait_until(lambda: len(ux_controls) >= 2, "center tap mapped to video", 5)
                assert all(abs(m.get("x", 0) - .5) < .02 and abs(m.get("y", 0) - .5) < .02 for _, m in ux_controls)
                ux_controls.clear()
                device("shell", "input", "swipe", str(cx), str(cy), str(cx), str(cy), "500")
                wait_until(lambda: any(m.get("phase") == "ended" for _, m in ux_controls), "stationary hold release", 5)
                down = next(t for t, m in ux_controls if m.get("phase") == "began")
                up = next(t for t, m in ux_controls if m.get("phase") == "ended")
                assert up - down > .2, "stationary hold was deferred until release"
                print("Android actual touch: letterbox rejection, center mapping and hold-before-release PASS", flush=True)
                assert not ux_errors, ux_errors
            finally:
                ux_stop.set()
                ux_peer.close()
                sender.join(timeout=6); reader.join(timeout=6)
'''
source = source.replace(marker, extra + "\n" + marker)
exec(compile(source, str(fixture), "exec"), {"__name__": "__main__", "__file__": str(fixture)})
