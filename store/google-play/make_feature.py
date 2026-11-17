"""Google Play feature graphic (1024 x 500), in the same style as the screenshots:
the brand backdrop, icon, name and tagline, and two phones from the screenshot set.
Run: python3 store/google-play/make_feature.py"""
import os, sys
from PIL import Image, ImageDraw
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import make_frames as mf

S = 2
W, H = 1024 * S, 500 * S
pano = mf.panorama()                       # 8640 x 1920
bg = pano.crop((1500, 0, 1500 + 3932, 1920)).resize((W, H)).convert('RGBA')

for raw, x, y, ang in (('04-present.png', 1220, 120, 8), ('01-chords.png', 1560, 70, -6)):
    dev = mf.phone(os.path.join(HERE, 'raw', raw), 560)
    mf.drop(bg, dev, x, y, angle=ang, blur=40, alpha=0.6, offset=(0, 30))

icon = Image.open(os.path.join(HERE, 'icon-512.png')).convert('RGB').resize((232, 232), Image.LANCZOS)
m = Image.new('L', icon.size, 0)
ImageDraw.Draw(m).rounded_rectangle([0, 0, 231, 231], radius=54, fill=255)
ic = icon.convert('RGBA'); ic.putalpha(m)
mf.drop(bg, ic, 128, 170, blur=26, alpha=0.55, offset=(0, 16))

d = ImageDraw.Draw(bg)
d.text((124, 470), 'ChordPro', font=mf.font('SferaDisplay-Bold.ttf', 124), fill=(255, 255, 255))
d.text((124, 600), 'Presenter', font=mf.font('SferaDisplay-Bold.ttf', 124), fill=(255, 255, 255))
d.text((130, 790), 'Your songbook for rehearsal and the stage', font=mf.font('Sfera-Regular.ttf', 50), fill=(178, 182, 194))
bg.convert('RGB').resize((1024, 500), Image.LANCZOS).save(os.path.join(HERE, 'feature-1024x500.png'))
print('ok')
