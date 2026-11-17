"""The website's phone screens: each 3x app capture (store/google-play/raw) with an Android status
bar on top and a gesture-bar strip with the home pill below, so nothing sits under the phone's
rounded corners. Writes img/phone-*.webp (480 px wide). Run: python3 store/website/make_phones.py"""
import os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
GP = os.path.join(os.path.dirname(HERE), 'google-play')
sys.path.insert(0, GP)
from make_frames import status_bar  # noqa: E402

# (store capture, or this folder's raw/p-*.png from capture_phone.py) -> img/phone-<name>.webp
SHOTS = [(os.path.join(GP, 'raw', n + '.png'), n[3:]) for n in
         ['01-chords', '02-editing', '03-format', '04-present', '05-tabs', '06-sheet', '07-phone', '08-export']]
SHOTS.append((os.path.join(HERE, 'raw', 'p-notation.png'), 'notation'))

for path, name in SHOTS:
    cap = Image.open(path).convert('RGB')
    w = cap.width
    dp = w / 411
    top_h, bot_h = round(30 * dp), round(22 * dp)
    top = cap.getpixel((w // 2, 4))
    bottom = cap.getpixel((w // 2, cap.height - 3))
    out = Image.new('RGB', (w, top_h + cap.height + bot_h), bottom)
    out.paste(status_bar(w, top_h, top), (0, 0))
    out.paste(cap, (0, top_h))
    lum = 0.299 * bottom[0] + 0.587 * bottom[1] + 0.114 * bottom[2]
    pill = (30, 30, 34) if lum > 140 else (230, 230, 236)
    d = ImageDraw.Draw(out)
    pw, ph = round(108 * dp), round(4 * dp)
    cy = top_h + cap.height + bot_h // 2
    d.rounded_rectangle([w // 2 - pw // 2, cy - ph // 2, w // 2 + pw // 2, cy + ph // 2], radius=ph // 2, fill=pill)
    small = out.resize((480, round(out.height * 480 / w)), Image.LANCZOS)
    small.save(os.path.join(HERE, 'img', f'phone-{name}.webp'), quality=78, method=6)
    print(name, small.size)
