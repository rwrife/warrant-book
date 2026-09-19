#!/usr/bin/env python3
"""Warrant Book brand asset generator (issue #7).

Deterministically renders the app icon (shield + checkmark) at every
Android mipmap density and iOS appiconset size, plus the centered splash
logo used by both platforms. The script is committed so any machine can
regenerate the exact same bytes:

    python3 tool/generate_brand_assets.py

Design tokens (kept in sync with ThemeData in lib/main.dart):
  seed green      #2E7D32  (Material green 800)
  deep green      #1B5E20  (Material green 900)
  check white     #FFFFFF
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SS = 8  # supersampling factor for crisp diagonal edges

GREEN = (0x2E, 0x7D, 0x32, 255)
DEEP = (0x1B, 0x5E, 0x20, 255)
WHITE = (255, 255, 255, 255)

# Canonical master at 1024 (also used for iOS 1024 and as the splash base).
MASTER = 1024


def shield_points(size: int) -> list[tuple[float, float]]:
    """Heraldic shield outline in a size x size box (2% inset)."""
    m = size * 0.02
    w = size
    return [
        (w * 0.14 + m, w * 0.08),
        (w * 0.50, w * 0.03),
        (w * 0.86 - m, w * 0.08),
        (w * 0.86 - m, w * 0.50),
        (w * 0.50, w * 0.95),
        (w * 0.14 + m, w * 0.50),
    ]


def draw_logo(size: int, *, full_bleed: bool = False) -> Image.Image:
    """Render the icon at `size` px with RGBA transparency.

    full_bleed=True fills the whole canvas (iOS 1024 master must be an
    opaque rectangle; the appiconset masks it). full_bleed=False keeps a
    transparent margin (Android adaptive-safe, splash-friendly).
    """
    canvas = size * SS
    img = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    if full_bleed:
        d.rectangle([0, 0, canvas, canvas], fill=GREEN)

    pts = [(x * SS, y * SS) for x, y in shield_points(size)]
    # Vertical gradient: green -> deep green top-to-bottom, clipped to the
    # shield outline.
    top, bottom = canvas * 0.0, canvas * 1.0
    grad = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    steps = 64
    for s in range(steps):
        y0 = top + (bottom - top) * s / steps
        y1 = top + (bottom - top) * (s + 1) / steps + 1
        t = s / (steps - 1)
        color = tuple(
            int(GREEN[c] + (DEEP[c] - GREEN[c]) * t) for c in range(3)
        ) + (255,)
        gd.rectangle([0, y0, canvas, y1], fill=color)
    mask = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(mask).polygon(pts, fill=255)
    img.paste(grad, (0, 0), mask)

    # Checkmark: thick polyline with round joints, centered in the shield.
    cx = canvas / 2
    cy = canvas * 0.46
    r = canvas * 0.21  # reach
    stroke = max(2, int(canvas * 0.115))
    check = [
        (cx - r, cy + r * 0.10),
        (cx - r * 0.28, cy + r * 0.78),
        (cx + r * 1.05, cy - r * 0.72),
    ]
    joint = stroke / 2
    for i in range(len(check) - 1):
        x0, y0 = check[i]
        x1, y1 = check[i + 1]
        d.line([check[i], check[i + 1]], fill=WHITE, width=stroke)
        d.ellipse([x0 - joint, y0 - joint, x0 + joint, y0 + joint], fill=WHITE)
        d.ellipse([x1 - joint, y1 - joint, x1 + joint, y1 + joint], fill=WHITE)

    img = img.resize((size, size), Image.Resampling.LANCZOS)
    if full_bleed:
        # App Store rules: the 1024 master must be opaque RGB (no alpha).
        img = img.convert("RGB")
    return img


ANDROID_DENSITIES = {
    "mipmap-mdpi": 48,
    "mipmap-hdpi": 72,
    "mipmap-xhdpi": 96,
    "mipmap-xxhdpi": 144,
    "mipmap-xxxhdpi": 192,
}

IOS_SIZES = {
    "Icon-App-20x20@1x.png": 20,
    "Icon-App-20x20@2x.png": 40,
    "Icon-App-20x20@3x.png": 60,
    "Icon-App-29x29@1x.png": 29,
    "Icon-App-29x29@2x.png": 58,
    "Icon-App-29x29@3x.png": 87,
    "Icon-App-40x40@1x.png": 40,
    "Icon-App-40x40@2x.png": 80,
    "Icon-App-40x40@3x.png": 120,
    "Icon-App-60x60@2x.png": 120,
    "Icon-App-60x60@3x.png": 180,
    "Icon-App-76x76@1x.png": 76,
    "Icon-App-76x76@2x.png": 152,
    "Icon-App-83.5x83.5@2x.png": 167,
    "Icon-App-1024x1024@1x.png": 1024,
}


def save(img: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, "PNG", optimize=True)


def main() -> None:
    manifest: dict[str, str] = {}

    for folder, px in ANDROID_DENSITIES.items():
        # Android launcher icons keep a transparent rounded margin.
        img = draw_logo(px)
        path = ROOT / "android/app/src/main/res" / folder / "ic_launcher.png"
        save(img, path)
        manifest[str(path.relative_to(ROOT))] = hashlib.sha256(
            path.read_bytes()).hexdigest()[:16]

    for name, px in IOS_SIZES.items():
        img = draw_logo(px, full_bleed=(px == MASTER))
        path = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset" / name
        save(img, path)
        manifest[str(path.relative_to(ROOT))] = hashlib.sha256(
            path.read_bytes()).hexdigest()[:16]

    # Splash logo: ~40% of the 1024 master, transparent margin.
    splash = draw_logo(408)
    path = ROOT / "android/app/src/main/res/drawable-nodpi/splash_logo.png"
    save(splash, path)
    manifest[str(path.relative_to(ROOT))] = hashlib.sha256(
        path.read_bytes()).hexdigest()[:16]

    launch = ROOT / "ios/Runner/Assets.xcassets/LaunchImage.imageset"
    for name in ("LaunchImage.png", "LaunchImage@2x.png", "LaunchImage@3x.png"):
        px = {"LaunchImage.png": 128, "LaunchImage@2x.png": 256,
              "LaunchImage@3x.png": 384}[name]
        save(draw_logo(px), launch / name)
        manifest[str((launch / name).relative_to(ROOT))] = hashlib.sha256(
            (launch / name).read_bytes()).hexdigest()[:16]

    out = ROOT / "tool/brand_assets.sha256"
    out.write_text("".join(
        f"{digest}  {rel}\n" for rel, digest in sorted(manifest.items())))
    print(f"wrote {len(manifest)} assets; manifest -> {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
