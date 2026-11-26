import sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W, H = 1320, 2868
RAW = sys.argv[1]; OUT = sys.argv[2]
SHOTS = [
    ("01_storage.png", 150, "See what fills\nyour iPhone", "1.25 TB of video, heavy Live Photos,\nRAW shots — found in a second."),
    ("02_similar.png", 150, "Keep the best shot.\nDelete the rest.", "Start with the safest 20%.\nFavorites are never touched."),
    ("03_formats.png", 560, "iPhone or iCloud?\nSee both.", "Know what deleting frees, and which\ncamera format eats the space."),
    ("05_apps.png", 150, "Honest about\nthe rest", "No app can clear other apps' caches.\nPhotoSweep shows you how, step by step."),
]

def font(size, weight):
    f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
    try: f.set_variation_by_name(weight)
    except Exception: pass
    return f

def rounded(img, r):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, img.size[0], img.size[1]), r, fill=255)
    out = Image.new("RGBA", img.size); out.paste(img, (0, 0), mask); return out

for name, top, title, sub in SHOTS:
    bg = Image.new("RGB", (W, H))
    d = ImageDraw.Draw(bg)
    for y in range(H):  # deep blue → black
        t = y / H
        d.line([(0, y), (W, y)], fill=(int(28*(1-t)+6), int(48*(1-t)+8), int(110*(1-t)+14)))
    tf, sf = font(112, "Bold"), font(50, "Regular")
    y = 170
    for line in title.split("\n"):
        w = d.textlength(line, font=tf); d.text(((W-w)/2, y), line, font=tf, fill="white"); y += 128
    y += 24
    for line in sub.split("\n"):
        w = d.textlength(line, font=sf); d.text(((W-w)/2, y), line, font=sf, fill=(190, 200, 225)); y += 64
    shot = Image.open(f"{RAW}/{name}").convert("RGB")
    shot = shot.crop((0, top, shot.width, shot.height))
    sw = 1110; sh = int(shot.height * sw / shot.width)
    shot = shot.resize((sw, sh), Image.LANCZOS)
    y0 = max(y + 80, H - sh + 40)  # short screens sit lower, never leave a gap at the bottom
    shot = shot.crop((0, 0, sw, min(sh, H - y0 + 60)))
    card = rounded(shot, 64)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(((W-sw)//2-6, y0-6, (W+sw)//2+6, y0+card.height+6), 70, fill=(0, 0, 0, 160))
    shadow = shadow.filter(ImageFilter.GaussianBlur(30))
    bg = Image.alpha_composite(bg.convert("RGBA"), shadow)
    ImageDraw.Draw(bg).rounded_rectangle(((W-sw)//2-3, y0-3, (W+sw)//2+3, y0+card.height+3), 66, outline=(90, 110, 170), width=3)
    bg.paste(card, ((W-sw)//2, y0), card)
    bg.convert("RGB").save(f"{OUT}/{name.replace('.png','.jpg')}", quality=92)
    print(name, bg.size)
