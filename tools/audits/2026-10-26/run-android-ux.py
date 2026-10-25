#!/usr/bin/env python3
"""Extend the existing disposable Android fixture with synthetic-video UX checks.

No installed app/device is modified. Uses the fixture's owned AVD, application,
forward and cleanup. Requires ffmpeg plus its documented Android prerequisites.
Pass --screenshots <ignored-local-directory>; image content is synthetic.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
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
                        while remaining:
                            data = ux_peer.recv(remaining)
                            if not data: return
                            remaining -= len(data)
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
                def metric_text():
                    return next((node.get("text", "") for node in tree().iter("node")
                                 if "正在接收" in node.get("text", "")
                                 and "请求 30" in node.get("text", "")), "")
                before = wait_until(metric_text, "synthetic video and default metrics overlay", 25)
                print("Android synthetic stream/default overlay: " + before, flush=True)
                if args.screenshots:
                    (args.screenshots / "android-synthetic-aspect.png").write_bytes(device("exec-out", "screencap", "-p"))
                tap("设置")
                tap("显示延迟和帧率")
                disabled = any(node.get("text") == "显示延迟和帧率" and node.get("checked") == "false"
                               for node in tree().iter("node"))
                assert disabled, "Metrics checkbox was not disabled"
                tap("完成")
                after = metric_text()
                print("Android metrics checkbox=false; old metric text still visible=" + str(bool(after)), flush=True)
                assert after, "Metrics-toggle defect changed; update audit"
                if args.screenshots:
                    (args.screenshots / "android-metrics-disabled.png").write_bytes(device("exec-out", "screencap", "-p"))
                assert not ux_errors, ux_errors
            finally:
                ux_stop.set()
                ux_peer.close()
                sender.join(timeout=6); reader.join(timeout=6)
'''
source = source.replace(marker, extra + "\n" + marker)
exec(compile(source, str(fixture), "exec"), {"__name__": "__main__", "__file__": str(fixture)})
