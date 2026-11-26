#!/usr/bin/env python3
"""Generate AppIcon.iconset PNGs + AppIcon.icns for ClearMMR (memory-chip glyph)."""
from PIL import Image, ImageDraw
import os

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

# nền bo góc gradient dọc (xanh đậm -> tím đậm)
top = (38, 52, 96)
bot = (18, 20, 38)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3)) + (255,))
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=int(S * 0.225), fill=255)
img.putalpha(mask)

d = ImageDraw.Draw(img)
amber = (255, 176, 32, 255)
dark = (20, 22, 40, 255)

# thân chip bo góc
top_y, bot_y = int(S * 0.30), int(S * 0.70)
left_x, right_x = int(S * 0.20), int(S * 0.80)
rad = int(S * 0.06)
d.rounded_rectangle([left_x, top_y, right_x, bot_y], radius=rad, fill=dark, outline=amber, width=int(S * 0.018))

# chân pin: 4 chân mỗi mép trên/dưới
pin_w = int(S * 0.018)
pin_h = int(S * 0.07)
for i in range(4):
    px = left_x + int((right_x - left_x) * (0.14 + 0.24 * i))
    d.rectangle([px - pin_w // 2, top_y - pin_h - int(S * 0.015), px + pin_w // 2, top_y - int(S * 0.015)], fill=amber)
    d.rectangle([px - pin_w // 2, bot_y + int(S * 0.015), px + pin_w // 2, bot_y + pin_h + int(S * 0.015)], fill=amber)

# 3 vạch trong thân chip gợi ý cell RAM
gap = int(S * 0.05)
for i in range(3):
    vx = left_x + int((right_x - left_x) * (0.25 + 0.25 * i))
    d.line([(vx, top_y + gap), (vx, bot_y - gap)], fill=amber, width=int(S * 0.012))

os.makedirs("build/iconset", exist_ok=True)
sizes = [16, 32, 128, 256, 512]
for s in sizes:
    img.resize((s, s), Image.LANCZOS).save(f"build/iconset/icon_{s}x{s}.png")
    img.resize((s * 2, s * 2), Image.LANCZOS).save(f"build/iconset/icon_{s}x{s}@2x.png")
img.save("Resources/AppIcon-1024.png")
print("iconset done")
