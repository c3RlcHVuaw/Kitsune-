# Draws the installer window background (660x400 pt, plus @2x): dark, a soft glow, an arrow between the two icons.
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

out = sys.argv[1]
FONT = "/System/Library/Fonts/Supplemental/Arial.ttf"
TITLE = "Kitsune/Unbounded.ttf"

def draw(scale):
    w, h = 660 * scale, 400 * scale
    img = Image.new("RGB", (w, h), (9, 8, 10))
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    ImageDraw.Draw(glow).ellipse((w * 0.25, h * 0.55, w * 0.75, h * 1.35), fill=(150, 60, 12))
    img = Image.blend(img, Image.composite(glow, img, glow.convert("L").filter(ImageFilter.GaussianBlur(70 * scale))), 0.55)
    d = ImageDraw.Draw(img)
    y = 190 * scale  # icon row
    # arrow between the app (x=170) and Applications (x=490)
    x1, x2 = 262 * scale, 398 * scale
    d.line((x1, y, x2, y), fill=(255, 140, 40), width=3 * scale)
    d.line((x2 - 12 * scale, y - 12 * scale, x2, y), fill=(255, 140, 40), width=3 * scale)
    d.line((x2 - 12 * scale, y + 12 * scale, x2, y), fill=(255, 140, 40), width=3 * scale)
    title = ImageFont.truetype(TITLE, 26 * scale)
    title.set_variation_by_axes([400])
    small = ImageFont.truetype(FONT, 14 * scale)
    d.text((w / 2, 52 * scale), "Kitsune", font=title, fill=(245, 235, 225), anchor="mm")
    d.text((w / 2, 340 * scale), "Перетащите Kitsune в Программы", font=small, fill=(150, 140, 135), anchor="mm")
    return img

draw(1).save(out)
draw(2).save(out.replace(".png", "@2x.png"))
