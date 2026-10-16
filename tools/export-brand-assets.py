#!/usr/bin/env python3
"""Reproduce existing-mark derivatives. Never remove its background or invent artwork."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET
from PIL import Image, ImageDraw, __version__

ROOT = Path(__file__).resolve().parents[1]
NS = "http://schemas.android.com/apk/res/android"


def png(image):
    output = io.BytesIO()
    image.save(output, format="PNG", optimize=False, compress_level=9)
    return output.getvalue()


def generate(root):
    spec = json.loads((root / "tools/brand-assets.json").read_text())
    source = (root / spec["master"]).read_bytes()
    if hashlib.sha256(source).hexdigest() != spec["sha256"]:
        raise ValueError("Brand source changed. Review the supplied master and update its explicit checksum before exporting.")
    icon = Image.open(io.BytesIO(source)).convert("RGB")
    if icon.size != (1024, 1024):
        raise ValueError("Expected the existing 1024px icon master")
    outputs = {}
    for folder in ("Mac/Assets.xcassets/AppIcon.appiconset", "iOS/Assets.xcassets/AppIcon.appiconset"):
        for item in json.loads((root / folder / "Contents.json").read_text())["images"]:
            size = round(float(item["size"].split("x")[0]) * float(item["scale"].rstrip("x")))
            outputs[folder + "/" + item["filename"]] = source if size == 1024 else png(icon.resize((size, size), Image.Resampling.LANCZOS))
    sizes = {"public/icon-256.png": 256, "iOS/Assets.xcassets/AppLogo.imageset/applogo.png": 512,
             "AndroidReceiver/app/src/main/res/drawable/app_logo.png": 512}
    for density, size in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]:
        sizes[f"AndroidReceiver/app/src/main/res/mipmap-{density}/ic_launcher.png"] = size
    for path, size in sizes.items():
        outputs[path] = png(icon.resize((size, size), Image.Resampling.LANCZOS))
    canvas = spec["adaptiveCanvasDp"] * spec["adaptiveRasterScale"]
    square = spec["adaptiveImageDp"] * spec["adaptiveRasterScale"]
    foreground = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    foreground.paste(icon.resize((square, square), Image.Resampling.LANCZOS), ((canvas - square) // 2,) * 2)
    outputs["AndroidReceiver/app/src/main/res/drawable-nodpi/ic_launcher_foreground.png"] = png(foreground)
    outputs["AndroidReceiver/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml"] = f'''<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="{NS}">
    <background android:drawable="@color/launcher_background" />
    <foreground android:drawable="@drawable/ic_launcher_foreground" />
</adaptive-icon>
'''.encode()
    outputs["AndroidReceiver/app/src/main/res/values/launcher_colors.xml"] = f'''<?xml version="1.0" encoding="utf-8"?>
<resources><color name="launcher_background">{spec["background"]}</color></resources>
'''.encode()
    return outputs, foreground


def verify_safe_area(foreground):
    """All colored ink must fit inside the documented 66dp safe-zone circle."""
    width = foreground.width
    center, radius = width / 2, width * 33 / 108
    for y in range(width):
        for x in range(width):
            r, g, b, a = foreground.getpixel((x, y))
            if a and max(r, g, b) - min(r, g, b) > 32:
                if (x + .5 - center) ** 2 + (y + .5 - center) ** 2 > radius ** 2:
                    raise ValueError("Colored brand mark extends beyond Android adaptive safe area")


def preview(foreground, destination):
    sheet = Image.new("RGB", (720, 360), "#EEF1F5")
    draw = ImageDraw.Draw(sheet)
    # Adaptive launcher viewport is 72dp inside the full 108dp layer.
    margin = round(foreground.width / 6)
    viewport = foreground.crop((margin, margin, foreground.width - margin, foreground.height - margin))
    base = Image.new("RGBA", viewport.size, "white"); base.alpha_composite(viewport)
    for row, background in enumerate(("#EEF1F5", "#101820")):
        draw.rectangle((0, row * 180, 720, (row + 1) * 180), fill=background)
        for column, shape in enumerate(("circle", "rounded", "square")):
            tile = base.resize((120, 120), Image.Resampling.LANCZOS)
            mask = Image.new("L", tile.size); mask_draw = ImageDraw.Draw(mask)
            if shape == "circle": mask_draw.ellipse((0, 0, 119, 119), fill=255)
            elif shape == "rounded": mask_draw.rounded_rectangle((0, 0, 119, 119), radius=30, fill=255)
            else: mask_draw.rectangle((0, 0, 119, 119), fill=255)
            sheet.paste(tile, (60 + column * 240, 20 + row * 180), mask)
            draw.text((60 + column * 240, 148 + row * 180), shape, fill="#334155" if row == 0 else "#FFFFFF")
    destination.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(destination)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--check", action="store_true")
    group.add_argument("--write", action="store_true")
    parser.add_argument("--preview", type=Path)
    args = parser.parse_args()
    if __version__ != "12.3.0":
        parser.error("Install tools/brand-requirements.txt for reproducible PNG bytes")
    try:
        outputs, foreground = generate(ROOT)
        verify_safe_area(foreground)
        drift = []
        for relative, data in outputs.items():
            path = ROOT / relative
            if args.write:
                path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
            elif not path.exists():
                drift.append(relative)
            elif path.suffix == ".png":
                actual, expected = Image.open(path), Image.open(io.BytesIO(data))
                if actual.size != expected.size or actual.mode != expected.mode or actual.tobytes() != expected.tobytes():
                    drift.append(relative)
            elif path.read_bytes() != data:
                drift.append(relative)
        manifest = ET.parse(ROOT / "AndroidReceiver/app/src/main/AndroidManifest.xml").getroot().find("application")
        if manifest.get("{" + NS + "}icon") != "@mipmap/ic_launcher":
            raise ValueError("Android manifest no longer selects the versioned adaptive icon")
        if drift:
            raise ValueError("Brand export drift; inspect then use --write:\n" + "\n".join(drift))
        if args.preview:
            preview(foreground, args.preview)
        print(f"Brand exports PASS: {len(outputs)} assets; colored mark stays inside 66dp safe area")
        return 0
    except (ValueError, OSError) as error:
        print(error, file=sys.stderr); return 1


if __name__ == "__main__":
    sys.exit(main())
