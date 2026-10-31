#!/usr/bin/env python3
"""Export original promotional layouts using the real, already-sanitized app shots.

Optional authoring tool: Python 3 + Pillow. The website itself has no dependencies.
No screenshot text or controls are generated, redrawn, or retouched.
"""

from pathlib import Path
import math

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "website/assets"
FONT_DIR = Path("/System/Library/Fonts/Supplemental")


def font(size, bold=False):
    local = FONT_DIR / ("Arial Bold.ttf" if bold else "Arial.ttf")
    return ImageFont.truetype(str(local) if local.exists() else ("DejaVuSans-Bold.ttf" if bold else "DejaVuSans.ttf"), size)


def backdrop(size, center, glow):
    width, height = size
    image = Image.new("RGB", size)
    pixels = image.load()
    for y in range(height):
        for x in range(width):
            distance = math.hypot((x / width - center[0]) * .9, (y / height - center[1]) * .8)
            amount = max(0, 1 - distance / .82) ** 2
            pixels[x, y] = tuple(round(19 + channel * amount) for channel in glow)
    return image


def tracking(draw, xy, text, size=17, fill="#c7b8ac", spacing=3):
    x, y = xy
    face = font(size, True)
    for character in text:
        draw.text((x, y), character, font=face, fill=fill)
        x += draw.textlength(character, font=face) + spacing


def rounded_image(canvas, source, xy, width, radius=20):
    image = Image.open(ASSETS / source).convert("RGB")
    height = round(image.height * width / image.width)
    image = image.resize((width, height), Image.Resampling.LANCZOS)
    mask = Image.new("L", image.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width - 1, height - 1), radius, fill=255)
    canvas.paste(image, xy, mask)
    return width, height


def social():
    image = backdrop((1200, 630), (.3, .5), (56, 30, 20))
    keyboard = Image.open(ASSETS / "keyboard-studio.webp").convert("RGB").resize((850, 567), Image.Resampling.LANCZOS)
    mask = Image.new("L", keyboard.size)
    mask_pixels = mask.load()
    for y in range(keyboard.height):
        for x in range(keyboard.width):
            mask_pixels[x, y] = round(215 * min(1, x / 180) * min(1, (keyboard.height - y) / 100))
    image.paste(keyboard, (350, 64), mask)
    rounded_image(image, "app-system.png", (876, 85), 242, 18)
    rounded_image(image, "app-icon.png", (60, 44), 49, 12)
    draw = ImageDraw.Draw(image)
    draw.text((123, 51), "Lumina", font=font(31, True), fill="#fff4eb")
    tracking(draw, (62, 135), "KEYBOARD BACKLIGHT CONTROL FOR MAC", 12, spacing=1.5)
    draw.text((57, 174), "Your keyboard.", font=font(65, True), fill="#fff7f0")
    draw.text((57, 249), "In the right light.", font=font(65, True), fill="#ffc79a")
    draw.multiline_text((63, 350), "A little light, right when you need it.\nFree. Open source. At home in your menu bar.", font=font(19), fill="#d5c4b8", spacing=10)
    tracking(draw, (63, 477), "SUN CYCLE   /   TIME SLOTS   /   IDLE TIMEOUT", 11, spacing=1.1)
    draw.rounded_rectangle((62, 534, 232, 576), 8, fill="#f7e4d2")
    draw.text((80, 546), "GET THE FREE BETA", font=font(12, True), fill="#2c211a")
    draw.text((249, 547), "macOS 14+ · Not Apple-notarized", font=font(12), fill="#bda899")
    draw.text((831, 602), "Real app UI · Illustrative device rendering", font=font(11), fill="#c3b6af")
    image.save(ASSETS / "lumina-social.png", optimize=True)


def feature(index, name, headline, description, screenshot, glow, accent):
    image = backdrop((900, 1440), (.5, .45), glow)
    draw = ImageDraw.Draw(image)
    tracking(draw, (70, 64), f"LUMINA   /   {index:02}   /   {name}", 15, accent, 2)
    draw.multiline_text((64, 132), headline, font=font(76, True), fill="#fff6ef", spacing=5)
    draw.multiline_text((70, 334), description, font=font(24), fill="#d8cbc6", spacing=12)
    if index == 1:
        draw.arc((98, 448, 802, 840), 188, 352, fill="#dba77470", width=2)
        draw.ellipse((116, 490, 152, 526), fill="#ffc48b")
        draw.ellipse((750, 480, 782, 512), fill="#b7a4ed")
    elif index == 2:
        tracking(draw, (110, 470), "18:00 — 22:00    /    22:00 — 01:00", 19, "#d7c5ff", 1.3)
    else:
        tracking(draw, (304, 466), "00 : 30", 43, "#d1e7ee", 5)
    rounded_image(image, screenshot, (108, 560), 684, 26)
    # A quiet footer sits outside the screenshot, preserving the UI's original pixels.
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 1387, 900, 1440), fill="#171519")
    draw.text((70, 1405), "Actual app interface · Sample settings", font=font(15), fill="#b5a7a5")
    draw.text((653, 1405), "FREE & OPEN SOURCE", font=font(12, True), fill=accent)
    image.save(ASSETS / f"lumina-feature-{index}.png", optimize=True)
    return image


if __name__ == "__main__":
    social()
    panels = [
        feature(1, "SUN CYCLE", "Sun goes down.\nKeys light up.", "Your night brightness, from sunset to sunrise.\nOff during daylight. Calculated on your Mac.", "app-sun-cycle.png", (116, 60, 32), "#e6bca0"),
        feature(2, "TIME SLOTS", "Your hours.\nYour brightness.", "Up to three daily slots, with their own brightness.\nFor evening focus and after-midnight plans.", "app-time-slots.png", (66, 46, 113), "#c9b8ee"),
        feature(3, "INACTIVITY TIMEOUT", "Step away.\nLights out.", "Set a timeout for the moments you’re away.\nResume your current mode when you return.", "app-idle.png", (27, 67, 79), "#a8c9d5"),
    ]
    combined = Image.new("RGB", (2400, 1280))
    for index, panel in enumerate(panels):
        combined.paste(panel.resize((800, 1280), Image.Resampling.LANCZOS), (index * 800, 0))
    combined.save(ASSETS / "lumina-features.png", optimize=True)
    print("Exported social cover, three feature posters, and the combined feature image.")
