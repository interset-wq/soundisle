#!/usr/bin/env python3
"""Render the Soundisle launcher icons from code.

The master artwork is drawn at 4x and downsampled, so the generated PNGs stay
crisp at every density. Run from the repository root:

    python3 scripts/generate_icons.py

Only Pillow is required. Afterwards rebuild the app for the new icon to show up.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "app"

MASTER = 1024
SS = 4  # supersampling factor
SIZE = MASTER * SS

# Palette
BG_TOP = (18, 52, 66)
BG_BOTTOM = (6, 13, 20)
GLOW = (24, 156, 142)
MINT = (156, 250, 222)
AQUA = (58, 219, 195)
DEEP = (16, 138, 128)
SEA = (78, 168, 176)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient(size, top, bottom, horizontal=False):
    img = Image.new("RGB", (size, size))
    px = img.load()
    for i in range(size):
        t = i / (size - 1)
        color = lerp(top, bottom, t)
        if horizontal:
            for j in range(size):
                px[i, j] = color
        else:
            for j in range(size):
                px[j, i] = color
    return img


def rounded_mask(size, radius_ratio=0.225):
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle(
        (0, 0, size - 1, size - 1), radius=round(size * radius_ratio), fill=255
    )
    return mask


def radial_glow(size, center, radius, color, strength=110):
    layer = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(layer)
    cx, cy = center
    steps = 40
    for i in range(steps, 0, -1):
        t = i / steps
        r = radius * t
        alpha = round(strength * (1 - t) ** 1.7)
        draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=alpha)
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.08 + size * 0.004))
    glow = Image.new("RGB", (size, size), color)
    return glow, layer


def bezier(points, samples=120):
    """Sample a cubic bezier from four control points."""
    out = []
    for i in range(samples + 1):
        t = i / samples
        mt = 1 - t
        x = (
            mt**3 * points[0][0]
            + 3 * mt * mt * t * points[1][0]
            + 3 * mt * t * t * points[2][0]
            + t**3 * points[3][0]
        )
        y = (
            mt**3 * points[0][1]
            + 3 * mt * mt * t * points[1][1]
            + 3 * mt * t * t * points[2][1]
            + t**3 * points[3][1]
        )
        out.append((x, y))
    return out


def draw_motif(size, scale=1.0):
    """Island + radiating sound arcs on a transparent canvas.

    Everything is expressed in 1024-design units and multiplied by `scale`
    around the canvas centre.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = size / 2
    cy = size / 2

    def P(x, y):
        return (cx + (x - 512) * scale, cy + (y - 512) * scale)

    def W(v):
        return v * scale

    # Soft halo behind the island.
    halo = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(halo)
    hx, hy = P(512, 588)
    hr = W(250)
    hdraw.ellipse((hx - hr, hy - hr, hx + hr, hy + hr), fill=(46, 214, 190, 46))
    halo = halo.filter(ImageFilter.GaussianBlur(W(70)))
    img = Image.alpha_composite(img, halo)
    draw = ImageDraw.Draw(img)

    # Sound arcs rising above the island.
    arc_specs = [
        (150, 11, (150, 246, 226, 150)),
        (210, 10, (96, 232, 208, 105)),
        (272, 8, (70, 205, 190, 66)),
    ]
    for radius, width, color in arc_specs:
        box = (cx - W(radius), cy - W(radius), cx + W(radius), cy + W(radius))
        draw.arc(box, start=203, end=337, fill=color, width=round(W(width)))

    # Sea ripples under the island.
    for y, half, width, alpha in (
        (816, 228, 9, 120),
        (858, 150, 8, 84),
        (893, 84, 7, 52),
    ):
        line = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        ldraw = ImageDraw.Draw(line)
        pts = [P(512 - half, y), P(512 + half, y)]
        ldraw.line(pts, fill=(*SEA, alpha), width=round(W(width)))
        img = Image.alpha_composite(img, line)
    draw = ImageDraw.Draw(img)

    # Island silhouette: a rounded dome with a flat shoreline.
    left = bezier([(300, 772), (306, 636), (398, 566), (512, 566)])
    right = bezier([(512, 566), (626, 566), (718, 636), (724, 772)])
    silhouette = left + right
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).polygon([P(x, y) for x, y in silhouette], fill=255)

    # Vertical mint-to-teal gradient inside the island.
    top_y = P(512, 556)[1]
    bottom_y = P(512, 790)[1]
    grad = Image.new("RGB", (size, size))
    gpx = grad.load()
    for y in range(size):
        t = min(1.0, max(0.0, (y - top_y) / max(1.0, bottom_y - top_y)))
        if t < 0.55:
            color = lerp(MINT, AQUA, t / 0.55)
        else:
            color = lerp(AQUA, DEEP, (t - 0.55) / 0.45)
        for x in range(size):
            gpx[x, y] = color
    island = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    island.paste(grad, (0, 0), mask)
    img = Image.alpha_composite(img, island)
    draw = ImageDraw.Draw(img)

    # Highlight along the top of the dome.
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hd = ImageDraw.Draw(highlight)
    arc_box = (cx - W(216), cy - W(216), cx + W(216), cy + W(216))
    hd.arc(arc_box, start=232, end=308, fill=(226, 255, 246, 120), width=round(W(9)))
    highlight = highlight.filter(ImageFilter.GaussianBlur(W(2)))
    img = Image.alpha_composite(img, highlight)

    # A small beacon dot floating above the dome, like a note in the air.
    dot = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot)
    dx, dy = P(512, 470)
    dr = W(17)
    dd.ellipse((dx - dr, dy - dr, dx + dr, dy + dr), fill=(214, 255, 243, 235))
    img = Image.alpha_composite(img, dot)
    return img


def compose(size, rounded, scale):
    bg = gradient(size, BG_TOP, BG_BOTTOM).convert("RGBA")
    glow, mask = radial_glow(size, (size * 0.5, size * 0.58), size * 0.55, GLOW, 120)
    bg = Image.composite(glow, bg, mask)

    motif = draw_motif(size, scale=scale)
    out = Image.alpha_composite(bg, motif)
    if rounded:
        out.putalpha(rounded_mask(size))
    return out


def resize(img, size):
    return img.resize((size, size), Image.LANCZOS)


def save_png(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path, format="PNG", optimize=True)


def parse_ios_size(name):
    m = re.match(r"Icon-App-([\d.]+)x([\d.]+)@(\d)x\.png$", name)
    if not m:
        return None
    return round(float(m.group(1)) * int(m.group(3)))


def main():
    # draw_motif works in 1024-design units, so the supersampling factor has to
    # be part of the scale or the artwork would only fill 1/SS of the canvas.
    master_full = compose(SIZE, rounded=False, scale=SS)
    master_full = resize(master_full, MASTER)

    master_rounded = master_full.copy()
    master_rounded.putalpha(rounded_mask(MASTER))

    # Adaptive foregrounds live on a 108dp canvas with a 66dp safe circle. The
    # motif already occupies roughly half of the canvas, so keeping it at the
    # master scale keeps it comfortably inside that circle.
    foreground = draw_motif(SIZE, scale=SS)
    foreground = resize(foreground, MASTER)

    (APP / "assets" / "branding").mkdir(parents=True, exist_ok=True)
    master_full.save(APP / "assets" / "branding" / "app_icon_1024.png", optimize=True)
    master_full.save(APP / "assets" / "branding" / "app_icon_master.png", optimize=True)
    foreground.save(APP / "assets" / "branding" / "app_icon_foreground.png", optimize=True)

    # Android legacy launcher icons.
    android_res = APP / "android" / "app" / "src" / "main" / "res"
    for density, px in {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192,
    }.items():
        save_png(resize(master_rounded, px), android_res / f"mipmap-{density}" / "ic_launcher.png")

    # Android adaptive icon foregrounds (108dp canvas, artwork inside safe zone).
    for density, px in {
        "mdpi": 108,
        "hdpi": 162,
        "xhdpi": 216,
        "xxhdpi": 324,
        "xxxhdpi": 432,
    }.items():
        save_png(resize(foreground, px), android_res / f"mipmap-{density}" / "ic_launcher_foreground.png")

    save_png(resize(master_rounded, 512), APP / "assets" / "branding" / "app_icon_512.png")

    # iOS: full-bleed square, iOS applies the mask itself.
    ios_dir = APP / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    if ios_dir.is_dir():
        for entry in ios_dir.glob("Icon-App-*.png"):
            px = parse_ios_size(entry.name)
            if px:
                save_png(resize(master_full, px), entry)

    # macOS: square art, the system masks it.
    macos_dir = APP / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    if macos_dir.is_dir():
        for entry in macos_dir.glob("app_icon_*.png"):
            m = re.search(r"app_icon_(\d+)\.png$", entry.name)
            if m:
                save_png(resize(master_full, int(m.group(1))), entry)

    # Web icons: regular and maskable variants.
    web_dir = APP / "web" / "icons"
    if web_dir.is_dir():
        save_png(resize(master_full, 192), web_dir / "Icon-192.png")
        save_png(resize(master_full, 512), web_dir / "Icon-512.png")
        save_png(resize(compose(SIZE, False, SS), 192), web_dir / "Icon-maskable-192.png")
        save_png(resize(compose(SIZE, False, SS), 512), web_dir / "Icon-maskable-512.png")
        save_png(resize(master_rounded, 64), APP / "web" / "favicon.png")

    # Windows .ico.
    ico_path = APP / "windows" / "runner" / "resources" / "app_icon.ico"
    if ico_path.parent.is_dir():
        icon = resize(master_rounded, 256)
        icon.save(ico_path, format="ICO", sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

    print("icons written")


if __name__ == "__main__":
    main()
