#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "packaging" / "macos" / "icon.iconset"


def rounded_mask(size: int, radius: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)
    return mask


def draw_icon(size: int = 1024) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    radius = int(size * 0.24)
    inset = int(size * 0.05)
    bg = (246, 248, 252, 235)
    draw.rounded_rectangle((inset, inset, size - inset, size - inset), radius=radius, fill=bg)
    cx = cy = size / 2
    outer = size * 0.31
    width = size * 0.065
    bbox = [cx - outer, cy - outer, cx + outer, cy + outer]
    draw.ellipse(bbox, outline=(180, 196, 214, 200), width=int(width))
    inner = outer - width * 1.8
    draw.ellipse([cx - inner, cy - inner, cx + inner, cy + inner], fill=(255, 255, 255, 130))
    font_path = "/System/Library/Fonts/Hiragino Sans GB.ttc"
    font = ImageFont.truetype(font_path, size=int(size * 0.34), index=0)
    text = "B"
    box = draw.textbbox((0, 0), text, font=font)
    tw, th = box[2] - box[0], box[3] - box[1]
    draw.text((cx - tw / 2 - box[0], cy - th / 2 - box[1] - size * 0.02), text, font=font, fill=(29, 29, 31, 255))
    shadow = img.filter(ImageFilter.GaussianBlur(size * 0.012))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.alpha_composite(shadow, (0, int(size * 0.012)))
    out.alpha_composite(img)
    mask = rounded_mask(size, radius)
    out.putalpha(mask)
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    master = draw_icon(1024)
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    for size in sizes:
        resized = master.resize((size, size), Image.Resampling.LANCZOS)
        resized.save(OUT_DIR / f"icon_{size}x{size}.png")
        if size <= 512:
            retina = master.resize((size * 2, size * 2), Image.Resampling.LANCZOS)
            retina.save(OUT_DIR / f"icon_{size}x{size}@2x.png")
    master.save(ROOT / "packaging" / "macos" / "icon.png")
    print(f"wrote {OUT_DIR}")


if __name__ == "__main__":
    main()
