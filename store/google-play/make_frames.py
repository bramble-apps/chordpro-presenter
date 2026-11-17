"""Google Play phone screenshots (1080 x 1920): one continuous brand backdrop that flows across all
eight images, a headline and subline in Sfera Display / Sfera, and the app screen in a drawn phone
(thin bezel, status bar). Shot 7 adds a TV showing the projector.

Run: python3 store/google-play/make_frames.py
Reads raw/*.png (3x captures from capture/capture.py) and frames_list.py; writes screenshots/NN.png."""
import math
import os
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from frames_list import FRAMES  # noqa: E402

FONTS = os.path.expanduser('~/.local/share/fonts/sfera')
W, H = 1080, 1920
N = len(FRAMES)


def font(name, size):
    return ImageFont.truetype(os.path.join(FONTS, name), size)


def hexc(h):
    h = h.lstrip('#')
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def overlay(canvas, alpha, rgb=(255, 255, 255)):
    canvas.alpha_composite(Image.merge('RGBA', [Image.new('L', alpha.size, c) for c in rgb] + [alpha]))


# ---------- backdrop: one wide panorama, sliced per screenshot ----------

# A dark "creator studio" backdrop: near-black charcoal with a faint cool tint, lit only by soft
# accent glows (cool blue, a little teal, one warm amber) and faint flowing lines.
STOPS = [(0.0, '#0C0D11'), (0.25, '#111319'), (0.5, '#0E1015'), (0.75, '#131519'), (1.0, '#0C0D11')]
GLOWS = [(70, 120, 255), (40, 190, 200), (255, 150, 60), (120, 100, 255)]


def panorama():
    pw = W * N
    strip = Image.new('RGB', (pw, 1))
    stops = [(t, hexc(c)) for t, c in STOPS]
    for x in range(pw):
        t = x / (pw - 1)
        for (t0, c0), (t1, c1) in zip(stops, stops[1:]):
            if t0 <= t <= t1:
                k = (t - t0) / (t1 - t0)
                strip.putpixel((x, 0), tuple(int(c0[i] + (c1[i] - c0[i]) * k) for i in range(3)))
                break
    bg = strip.resize((pw, H)).convert('RGBA')
    # darker toward the bottom
    overlay(bg, Image.linear_gradient('L').resize((pw, H)).point(lambda v: int(v * 0.5)), (4, 4, 6))
    # soft accent glows, like stage lights in a dark studio
    rnd = random.Random(7)
    for k, rgb in enumerate(GLOWS):
        glow = Image.new('L', (pw, H), 0)
        gd = ImageDraw.Draw(glow)
        for _ in range(N // 2 + (k == 0)):
            cx, cy, r = rnd.uniform(0, pw), rnd.uniform(-300, 1500), rnd.uniform(320, 620)
            gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=rnd.randint(26, 40) if k != 2 else 22)
        overlay(bg, glow.filter(ImageFilter.GaussianBlur(240)), rgb)
    # flowing lines that continue from one screenshot to the next
    lines = Image.new('L', (pw * 2, H * 2), 0)
    ld = ImageDraw.Draw(lines)
    for base, amp, period, phase, alpha, width in [
            (1180, 210, 2.1, 0.0, 30, 4), (1250, 240, 2.1, 0.5, 20, 3), (1330, 190, 2.6, 1.3, 14, 3),
            (980, 160, 3.2, 2.2, 12, 2)]:
        pts = [(x, base * 2 + amp * 2 * math.sin(x / (2 * W) * math.tau / period + phase))
               for x in range(0, pw * 2 + 1, 8)]
        ld.line(pts, fill=alpha, width=width * 2, joint='curve')
    overlay(bg, lines.resize((pw, H), Image.LANCZOS))
    # fine grain so the gradient doesn't band
    overlay(bg, Image.effect_noise((pw, H), 24).point(lambda v: max(0, (v - 128)) // 6))
    return bg


# ---------- device ----------

MATERIAL = os.path.expanduser('~/development/flutter/bin/cache/artifacts/material_fonts')


def status_bar(width, height, bg_rgb):
    """An Android status bar as a Pixel draws it, in dp of a 411 dp wide phone: 28 dp tall, the
    clock in Roboto Medium 14 sp on the left, Android's own signal / Wi-Fi / battery icons
    (Material icon font) at 16 dp on the right, both kept clear of the rounded screen corners."""
    bar = Image.new('RGB', (width, height), bg_rgb)
    lum = 0.299 * bg_rgb[0] + 0.587 * bg_rgb[1] + 0.114 * bg_rgb[2]
    ink = (28, 27, 31) if lum > 140 else (242, 242, 246)
    d = ImageDraw.Draw(bar)
    dp = width / 411
    mid = height / 2
    inset = 24 * dp
    clock = ImageFont.truetype(os.path.join(MATERIAL, 'Roboto-Medium.ttf'), round(14 * dp))
    d.text((inset, mid), '9:30', font=clock, fill=ink, anchor='lm')
    icons = ImageFont.truetype(os.path.join(MATERIAL, 'MaterialIcons-Regular.otf'), round(16 * dp))
    x = width - inset
    # battery (upright, as Android shows it), Wi-Fi, mobile signal, right to left
    for cp, gap in ((0xf5af, 2), (0xf02bf, 3), (0xf017b, 0)):
        glyph = chr(cp)
        w = d.textlength(glyph, font=icons)
        d.text((x - w, mid), glyph, font=icons, fill=ink, anchor='lm')
        x -= w + gap * dp
    return bar


def phone(raw_path, sw):
    """The app capture inside a drawn phone; returns an RGBA image of the whole device."""
    cap = Image.open(raw_path).convert('RGB')
    bar_h = round(cap.width * 28 / 411)  # 28 dp
    top = cap.getpixel((cap.width // 2, 6))
    screen = Image.new('RGB', (cap.width, cap.height + bar_h), top)
    screen.paste(status_bar(cap.width, bar_h, top), (0, 0))
    screen.paste(cap, (0, bar_h))
    sh = int(screen.height * sw / screen.width)
    screen = screen.resize((sw, sh), Image.LANCZOS)

    bezel, rim, R, side = 15, 4, 104, 8
    ow, oh = sw + 2 * (bezel + rim), sh + 2 * (bezel + rim)
    dev = Image.new('RGBA', (ow + 2 * side, oh), (0, 0, 0, 0))
    d = ImageDraw.Draw(dev)
    for y0, y1 in ((330, 470), (520, 640)):  # side buttons
        d.rounded_rectangle([ow + side - 3, y0, ow + 2 * side - 1, y1], radius=4, fill=(64, 64, 72))
    body = Image.new('RGBA', (ow, oh), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle([0, 0, ow - 1, oh - 1], radius=R, fill=(10, 10, 12, 255))
    rim_mask = Image.new('L', (ow, oh), 0)
    ImageDraw.Draw(rim_mask).rounded_rectangle([0, 0, ow - 1, oh - 1], radius=R, outline=255, width=rim)
    shine = Image.linear_gradient('L').rotate(-35).resize((ow, oh)).point(lambda v: 80 + v // 2)
    body.alpha_composite(Image.merge('RGBA', [shine, shine, shine.point(lambda v: min(255, v + 12)), rim_mask]))
    dev.alpha_composite(body, (side, 0))
    m = Image.new('L', (sw, sh), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, sw - 1, sh - 1], radius=R - rim - bezel, fill=255)
    dev.paste(screen, (side + rim + bezel, rim + bezel), m)
    glass = Image.new('L', (sw, sh), 0)  # faint reflection across the top-left
    ImageDraw.Draw(glass).polygon([(0, 0), (int(sw * 0.55), 0), (0, int(sh * 0.32))], fill=14)
    glass = ImageChops.multiply(glass.filter(ImageFilter.GaussianBlur(40)), m)
    g = Image.new('RGBA', (sw, sh), (255, 255, 255, 0))
    g.putalpha(glass)
    dev.alpha_composite(g, (side + rim + bezel, rim + bezel))
    return dev


def tv(raw_path, tw):
    img = Image.open(raw_path).convert('RGB')
    th = int(tw * 9 / 16)
    img = img.resize((tw, th), Image.LANCZOS)
    b = 12
    out = Image.new('RGBA', (tw + 2 * b, th + 2 * b + 70), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle([0, 0, tw + 2 * b - 1, th + 2 * b - 1], radius=16, fill=(14, 14, 17))
    d.rounded_rectangle([0, 0, tw + 2 * b - 1, th + 2 * b - 1], radius=16, outline=(74, 74, 84), width=2)
    out.paste(img, (b, b))
    cx = out.width // 2
    d.polygon([(cx - 26, th + 2 * b), (cx + 26, th + 2 * b), (cx + 34, th + 2 * b + 52), (cx - 34, th + 2 * b + 52)], fill=(38, 38, 44))
    d.rounded_rectangle([cx - 190, th + 2 * b + 50, cx + 190, th + 2 * b + 64], radius=7, fill=(48, 48, 56))
    return out


def drop(canvas, obj, x, y, angle=0, blur=46, alpha=0.55, offset=(0, 34)):
    """Composite obj at (x, y) (rotation keeps the centre) with a soft shadow; parts off the canvas are cut."""
    if angle:
        cx, cy = x + obj.width / 2, y + obj.height / 2
        obj = obj.rotate(angle, expand=True, resample=Image.BICUBIC)
        x, y = int(cx - obj.width / 2), int(cy - obj.height / 2)
    pad = blur * 3
    a = Image.new('L', (obj.width + 2 * pad, obj.height + 2 * pad), 0)
    a.paste(obj.getchannel('A').point(lambda v: int(v * alpha)), (pad, pad))
    sh = Image.new('RGBA', a.size, (5, 3, 18, 255))
    sh.putalpha(a.filter(ImageFilter.GaussianBlur(blur)))
    layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))

    def paste(img, px, py):
        lft, top = max(0, -px), max(0, -py)
        rgt, bot = min(img.width, canvas.width - px), min(img.height, canvas.height - py)
        if rgt > lft and bot > top:
            layer.alpha_composite(img.crop((lft, top, rgt, bot)), (px + lft, py + top))

    paste(sh, x - pad + offset[0], y - pad + offset[1])
    paste(obj, x, y)
    canvas.alpha_composite(layer)


# ---------- text ----------

def wrap(draw, text, f, width):
    lines, line = [], ''
    for word in text.split():
        trial = (line + ' ' + word).strip()
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def headline(canvas, title, sub):
    d = ImageDraw.Draw(canvas)
    hf = font('SferaDisplay-Bold.ttf', 84)
    sf = font('Sfera-Regular.ttf', 40)
    y = 132
    for line in wrap(d, title, hf, W - 120):
        d.text((W / 2, y), line, font=hf, fill=(255, 255, 255), anchor='ma')
        y += 96
    y += 14
    for line in wrap(d, sub, sf, W - 200):
        d.text((W / 2, y), line, font=sf, fill=(178, 182, 194), anchor='ma')
        y += 54
    return y


def render():
    pano = panorama()
    os.makedirs(os.path.join(HERE, 'screenshots'), exist_ok=True)
    for i, f in enumerate(FRAMES):
        raw, title, sub = f[0], f[1], f[2]
        tv_raw = f[5] if len(f) > 5 else None
        style = (f[6] if len(f) > 6 else None) or {}
        canvas = pano.crop((i * W, 0, (i + 1) * W, H))
        y = headline(canvas, title, sub)
        if tv_raw:
            t = tv(os.path.join(HERE, 'raw', tv_raw), 940)
            drop(canvas, t, (W - t.width) // 2, y + 56, blur=34, alpha=0.6, offset=(0, 26))
            y = y + 56 + t.height - 150
        dev = phone(os.path.join(HERE, 'raw', raw), style.get('w', 800))
        x = (W - dev.width) // 2 + style.get('dx', 0)
        drop(canvas, dev, x, y + 70 + style.get('dy', 0), angle=style.get('angle', 0))
        out = os.path.join(HERE, 'screenshots', f'{i + 1:02d}.png')
        canvas.convert('RGB').save(out)
        print(out)


if __name__ == '__main__':
    render()
