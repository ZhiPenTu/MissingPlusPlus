#!/usr/bin/env python3
"""Generate the app icon (.appiconset PNGs + legacy .icns) and the
5 mood-colored menu bar template images for the 心安日记 (MissingPlusPlus) project.

Output:
  MissingPlusPlus/Assets.xcassets/AppIcon.appiconset/icon_*.png
  build/icon-source/AppIcon.icns  (legacy)
  MissingPlusPlus/Resources/MenuBarIcon.png + MenuBarIcon-{1x,2x,3x}.png
  MissingPlusPlus/Resources/MenuBarIcon-{mood}.png  (5 mood variants)

Run from the project root:
    python3 scripts/make-icons.py
"""
from __future__ import annotations

import json
import math
import os
import shutil
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter


PROJECT_ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = PROJECT_ROOT / "build" / "icon-source"
OUT_DIR.mkdir(parents=True, exist_ok=True)

ICON_SIZES = [16, 32, 64, 128, 256, 512, 1024]

# Menu bar color palette per Mood. Keys match Mood.rawValue.
# (top, bottom) RGB tuples — gentle vertical gradient on the heart, matches
# the app icon's squircle style.
MOOD_PALETTE: dict[str, tuple[tuple[int, int, int], tuple[int, int, int]]] = {
    "happy":     ((255, 200, 87),  (255, 159, 67)),    # warm gold -> orange
    "joyful":    ((110, 220, 130), (52, 187, 100)),    # leaf green
    "delighted": ((233, 30, 99),   (255, 105, 130)),   # rose -> coral
    "sad":       ((91, 122, 153),  (66, 96, 130)),     # steel blue
    "longing":   ((155, 114, 207), (123, 84, 175)),    # lavender
}


# ---------- shape helpers ----------

def heart_points(box: int, num_points: int = 360, padding: float = 0.10) -> list[tuple[float, float]]:
    s = box * (1.0 - 2.0 * padding)
    pts = []
    for i in range(num_points):
        t = 2.0 * math.pi * i / num_points
        x = 16.0 * math.sin(t) ** 3
        y = -(13.0 * math.cos(t) - 5.0 * math.cos(2 * t) - 2.0 * math.cos(3 * t) - math.cos(4 * t))
        scale = s / 29.0
        px = box / 2.0 + x * scale
        py = box / 2.0 + (y + 2.5) * scale
        pts.append((px, py))
    return pts


def squircle_mask(size: int, radius_ratio: float = 0.2237) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    radius = int(size * radius_ratio)
    ImageDraw.Draw(mask).rounded_rectangle(
        [(0, 0), (size - 1, size - 1)], radius=radius, fill=255
    )
    return mask


def vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    grad = Image.new("RGB", (1, size))
    px = grad.load()
    for y in range(size):
        t = y / (size - 1)
        px[0, y] = (
            int(top[0] * (1.0 - t) + bottom[0] * t),
            int(top[1] * (1.0 - t) + bottom[1] * t),
            int(top[2] * (1.0 - t) + bottom[2] * t),
        )
    grad = grad.resize((size, size), Image.BILINEAR).convert("RGBA")
    return grad


# ---------- icon rendering ----------

def render_app_icon(size: int) -> Image.Image:
    """Default app icon: pink-to-coral squircle + white heart."""
    bg = vertical_gradient(size, (255, 107, 138), (255, 143, 168))
    mask = squircle_mask(size)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)

    heart_box = int(size * 0.62)
    heart_pts = heart_points(heart_box, padding=0.0)
    cx = cy = size / 2.0
    heart_pts = [(x - heart_box / 2.0 + cx, y - heart_box / 2.0 + cy) for x, y in heart_pts]

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_offset = max(2, int(size * 0.012))
    sh_pts = [(x, y + sh_offset) for x, y in heart_pts]
    sh_draw.polygon(sh_pts, fill=(180, 40, 70, 90))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, int(size * 0.008))))
    out = Image.alpha_composite(out, shadow)

    heart = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(heart).polygon(heart_pts, fill=(255, 255, 255, 255))
    out = Image.alpha_composite(out, heart)

    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_radius = max(2, int(size * 0.06))
    hl_cx, hl_cy = int(size * 0.35), int(size * 0.30)
    hl_draw.ellipse(
        [(hl_cx - hl_radius, hl_cy - hl_radius), (hl_cx + hl_radius, hl_cy + hl_radius)],
        fill=(255, 255, 255, 70),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=hl_radius * 0.6))
    out = Image.alpha_composite(out, highlight)
    return out


def render_mood_app_icon(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    """Like render_app_icon but with a custom palette (for the alternative
    app icon variants). Tinted heart-on-squircle, sized like the default."""
    bg = vertical_gradient(size, top, bottom)
    mask = squircle_mask(size)
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), mask)

    heart_box = int(size * 0.62)
    heart_pts = heart_points(heart_box, padding=0.0)
    cx = cy = size / 2.0
    heart_pts = [(x - heart_box / 2.0 + cx, y - heart_box / 2.0 + cy) for x, y in heart_pts]

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_offset = max(2, int(size * 0.012))
    sh_pts = [(x, y + sh_offset) for x, y in heart_pts]
    # Tinted shadow (a darker shade of the palette) for cohesion.
    sh_color = (max(0, top[0] - 60), max(0, top[1] - 60), max(0, top[2] - 60), 90)
    sh_draw.polygon(sh_pts, fill=sh_color)
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, int(size * 0.008))))
    out = Image.alpha_composite(out, shadow)

    heart = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(heart).polygon(heart_pts, fill=(255, 255, 255, 255))
    out = Image.alpha_composite(out, heart)

    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_radius = max(2, int(size * 0.06))
    hl_cx, hl_cy = int(size * 0.35), int(size * 0.30)
    hl_draw.ellipse(
        [(hl_cx - hl_radius, hl_cy - hl_radius), (hl_cx + hl_radius, hl_cy + hl_radius)],
        fill=(255, 255, 255, 70),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=hl_radius * 0.6))
    out = Image.alpha_composite(out, highlight)
    return out


def render_mood_icon(size: int, mood_key: str) -> Image.Image:
    """Solid-colored heart on transparent background, for the menu bar.
    The image is rendered in full color (not template) so the mood color
    is the actual UI accent.
    """
    if mood_key not in MOOD_PALETTE:
        raise KeyError(f"unknown mood: {mood_key}")
    top, bottom = MOOD_PALETTE[mood_key]
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))

    # Subtle gradient
    grad = vertical_gradient(size, top, bottom)

    # Heart shadow
    heart_box = int(size * 0.78)
    heart_pts = heart_points(heart_box, padding=0.0)
    cx = cy = size / 2.0
    heart_pts = [(x - heart_box / 2.0 + cx, y - heart_box / 2.0 + cy) for x, y in heart_pts]

    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shadow)
    sh_offset = max(1, int(size * 0.018))
    sh_pts = [(x, y + sh_offset) for x, y in heart_pts]
    sh_draw.polygon(sh_pts, fill=(0, 0, 0, 60))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(1, int(size * 0.012))))
    img = Image.alpha_composite(img, shadow)

    # Heart fill
    heart_layer = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask_layer = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask_layer).polygon(heart_pts, fill=255)
    heart_layer.paste(grad, (0, 0), mask_layer)
    img = Image.alpha_composite(img, heart_layer)

    # Highlight bump
    highlight = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    hl_draw = ImageDraw.Draw(highlight)
    hl_radius = max(1, int(size * 0.06))
    hl_cx, hl_cy = int(size * 0.36), int(size * 0.30)
    hl_draw.ellipse(
        [(hl_cx - hl_radius, hl_cy - hl_radius), (hl_cx + hl_radius, hl_cy + hl_radius)],
        fill=(255, 255, 255, 90),
    )
    highlight = highlight.filter(ImageFilter.GaussianBlur(radius=hl_radius * 0.6))
    img = Image.alpha_composite(img, highlight)

    return img


# ---------- main ----------

def main() -> None:
    print(f"==> writing icons to {OUT_DIR}")

    # 1. App icon master
    master = render_app_icon(1024)
    master.save(OUT_DIR / "appicon-1024.png")
    print("  saved appicon-1024.png")

    # 2. App icon downsamples -> .appiconset (this is what Xcode picks up)
    appiconset = PROJECT_ROOT / "MissingPlusPlus" / "Assets.xcassets" / "AppIcon.appiconset"
    appiconset.mkdir(parents=True, exist_ok=True)
    mapping = {
        (16, 1): "icon_16x16.png",
        (16, 2): "icon_16x16@2x.png",
        (32, 1): "icon_32x32.png",
        (32, 2): "icon_32x32@2x.png",
        (128, 1): "icon_128x128.png",
        (128, 2): "icon_128x128@2x.png",
        (256, 1): "icon_256x256.png",
        (256, 2): "icon_256x256@2x.png",
        (512, 1): "icon_512x512.png",
        (512, 2): "icon_512x512@2x.png",
    }
    for (logical, scale), name in mapping.items():
        target = logical * scale
        out = master.resize((target, target), Image.LANCZOS)
        out.save(appiconset / name)
        print(f"  saved {appiconset.name}/{name} ({target}x{target})")

    # 3. Per-mood AppIcon .icns (for runtime app icon switching).
    #    The .appiconset is the "neutral" default. For each mood we also build
    #    a parallel *.iconset folder (which iconutil accepts), then run
    #    iconutil to compile the .icns. The runtime code loads these via
    #    Bundle.main.url(forResource:withExtension:) and feeds them to
    #    NSApplication.setApplicationIconImage().
    iconsets_dir = PROJECT_ROOT / "build" / "alt-iconsets"
    iconsets_dir.mkdir(parents=True, exist_ok=True)
    for mood_key, palette in MOOD_PALETTE.items():
        # Render the same squircle + heart design, but tinted with the mood palette
        # instead of the neutral pink.
        top, bottom = palette
        # We need a custom render here because render_app_icon() uses a fixed palette.
        mood_master = render_mood_app_icon(1024, top, bottom)
        iconset = iconsets_dir / f"AppIcon-{mood_key}.iconset"
        iconset.mkdir(exist_ok=True)
        for (logical, scale), name in mapping.items():
            target = logical * scale
            out = mood_master.resize((target, target), Image.LANCZOS)
            out.save(iconset / name)
        icns_out = OUT_DIR / f"AppIcon-{mood_key}.icns"
        os.system(f'iconutil -c icns "{iconset}" -o "{icns_out}" 2>/dev/null')
        if icns_out.exists():
            print(f"  built {icns_out.name} ({icns_out.stat().st_size} bytes)")

    # 4. (no global .icns build — .appiconset is the source of truth for modern Xcode.)

    # 4. Resources: menu bar icons for each mood (full color, 22/44/66)
    resources = PROJECT_ROOT / "MissingPlusPlus" / "Resources"
    resources.mkdir(parents=True, exist_ok=True)
    for mood_key in MOOD_PALETTE:
        for tag, sz in [("1x", 22), ("2x", 44), ("3x", 66)]:
            img = render_mood_icon(sz, mood_key)
            img.save(resources / f"MenuBarIcon-{mood_key}-{tag}.png")
        # main per-mood entry the AppDelegate loads:
        shutil.copy2(resources / f"MenuBarIcon-{mood_key}-2x.png",
                     resources / f"MenuBarIcon-{mood_key}.png")
        print(f"  saved MenuBarIcon-{mood_key}.png (1x/2x/3x)")

    # 5. Default menu bar (used when no entry has been recorded yet) —
    #    neutral white-on-transparent so the system tints it.
    default = Image.new("RGBA", (44, 44), (0, 0, 0, 0))
    pts = heart_points(44, padding=0.10)
    ImageDraw.Draw(default).polygon(pts, fill=(255, 255, 255, 255))
    for tag, sz in [("1x", 22), ("2x", 44), ("3x", 66)]:
        if sz == 22:
            default.save(resources / f"MenuBarIcon-1x.png")
        elif sz == 44:
            default.save(resources / f"MenuBarIcon-2x.png")
        else:
            default.save(resources / f"MenuBarIcon-3x.png")
    shutil.copy2(resources / "MenuBarIcon-2x.png", resources / "MenuBarIcon.png")
    print("  saved neutral MenuBarIcon.png (template)")

    print("==> done")


if __name__ == "__main__":
    main()
