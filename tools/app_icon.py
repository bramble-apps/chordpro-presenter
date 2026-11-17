"""ChordPro Presenter app icon: thick extruded ChordPro brackets on a dark
GNOME-Terminal-style tile. Renders the masters into assets/app_icon/ and
exports every platform's icon files (web, Android, iOS, macOS, Windows).
Run from the repo root:  python3 tools/app_icon.py   (needs Pillow)"""
import json, os
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=3; W=1024*S
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def fill(stops,box):
    x0,y0,x1,y1=[int(v*S) for v in box]
    g=Image.new('RGB',(1,256))
    for k in range(256):
        t=k/255
        for i in range(len(stops)-1):
            (p0,c0),(p1,c1)=stops[i],stops[i+1]
            if p0<=t<=p1: g.putpixel((0,k),lerp(hexc(c0),hexc(c1),(t-p0)/max(p1-p0,1e-6))); break
    img=Image.new('RGB',(W,W),hexc(stops[-1][1]))
    img.paste(Image.new('RGB',(W,y0),hexc(stops[0][1])),(0,0))
    img.paste(g.resize((W,y1-y0),Image.BICUBIC),(0,y0))
    return img
def solid(c): return Image.new('RGB',(W,W),hexc(c))
def alpha(m,a): return m.point(lambda v:int(v*a))
def rrect(box,r):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).rounded_rectangle([v*S for v in box],radius=r*S,fill=255); return m
def poly(pts,r=0):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).polygon([(x*S,y*S) for x,y in pts],fill=255)
    return m.filter(ImageFilter.GaussianBlur(r*S)).point(lambda v:255 if v>128 else 0) if r else m
def sub(a,b): return ImageChops.subtract(a,b)
def mul(a,b): return ImageChops.multiply(a,b)
def blur(m,r): return m.filter(ImageFilter.GaussianBlur(r*S))
def shift(m,dx,dy): return ImageChops.offset(m,int(dx*S),int(dy*S))
def union(*ms):
    m=ms[0]
    for x in ms[1:]: m=ImageChops.lighter(m,x)
    return m

def render(path,mode='shadow',lyrics=False):
    img=Image.new('RGBA',(W,W),(0,0,0,0))
    def put(src,m,a=1.0):
        nonlocal img
        layer=(src if isinstance(src,Image.Image) else solid(src)).convert('RGBA')
        layer.putalpha(alpha(m,a) if a!=1 else m); img=Image.alpha_composite(img,layer)

    R=0 if mode=='square' else 228
    tile=rrect((0,0,1023,1023),R)
    # dark base edge under the face, visible as a thick band at the bottom
    put(fill([(0,'#1E1A26'),(0.85,'#16131C'),(1,'#0C0A10')],(0,0,1024,1024)),tile)
    # dark face sits on top of the base
    face=rrect((0,0,1023,966),R)
    put(fill([(0,'#3D3846'),(0.5,'#2E2A36'),(1,'#241F31')],(0,0,1024,966)),face)
    # subtle lighter rim along the bottom of the edge band
    put('#FFFFFF',mul(sub(tile,face),sub(tile,shift(tile,0,-3))),0.12)
    # crisp 1-2px highlight along the very top edge of the face, like Adwaita bevels
    put('#FFFFFF',sub(face,shift(face,0,4)),0.22)

    # ---- thick, sharp-edged extruded brackets ----
    T=140; ARM=252; Y0,Y1=200,750; DEPTH=28
    L0,R1=168,856
    def bracket(left):
        if left:
            x0,x1=L0,L0+ARM
            pts=[(x0,Y0),(x1,Y0),(x1,Y0+T),(x0+T,Y0+T),(x0+T,Y1-T),(x1,Y1-T),(x1,Y1),(x0,Y1)]
        else:
            x0,x1=R1-ARM,R1
            pts=[(x1,Y0),(x0,Y0),(x0,Y0+T),(x1-T,Y0+T),(x1-T,Y1-T),(x0,Y1-T),(x0,Y1),(x1,Y1)]
        return poly(pts,5)     # tiny radius: Adwaita-sharp, not blobby
    b=union(bracket(True),bracket(False))
    side=union(*[shift(b,0,d) for d in range(0,DEPTH+1,2)])   # extrusion volume
    # shadow cast on the dark face
    put('#000000',shift(blur(union(b,side),14),0,26),0.55)
    # extrusion side (darker grey, like the terminal's base edge)
    put(fill([(0,'#9A9996'),(1,'#5E5C64')],(0,Y0,1024,Y1+DEPTH)),side)
    # front face (light grey)
    put(fill([(0,'#F6F5F4'),(0.55,'#DEDDDA'),(1,'#C0BFBC')],(0,Y0,1024,Y1)),b)
    # bevel: bright top edges, slightly darker bottom edges of the front face
    put('#FFFFFF',sub(b,shift(b,0,4)),0.9)
    put('#77767B',mul(b,sub(b,shift(b,0,-3))),0.5)

    if lyrics:
        lines=union(*[rrect((x0,y,x1,y+36),7) for x0,x1,y in [(352,672,384),(386,638,460),(352,672,536)]])
        put('#000000',shift(blur(lines,3),0,6),0.4)
        put('#F6F5F4',lines)
        put('#FFFFFF',sub(lines,shift(lines,0,3)),0.6)

    if mode!='shadow':
        out=img.convert('RGB') if mode=='square' else img
        out.resize((1024,1024),Image.LANCZOS).save(path); return
    # shrink onto a padded canvas and add an exterior drop shadow
    PAD=72; size=W-2*PAD*S
    icon=img.resize((size,size),Image.LANCZOS)
    a=icon.getchannel('A')
    canvas=Image.new('RGBA',(W,W),(0,0,0,0))
    sh=Image.new('L',(W,W),0); sh.paste(a,(PAD*S,PAD*S+18*S))
    sh=sh.filter(ImageFilter.GaussianBlur(22*S)).point(lambda v:int(v*0.45))
    canvas.putalpha(sh)
    tight=Image.new('L',(W,W),0); tight.paste(a,(PAD*S,PAD*S+5*S))
    t2=Image.new('RGBA',(W,W),(0,0,0,0)); t2.putalpha(tight.filter(ImageFilter.GaussianBlur(4*S)).point(lambda v:int(v*0.35)))
    canvas=Image.alpha_composite(canvas,t2)
    canvas.alpha_composite(icon,(PAD*S,PAD*S))
    canvas.resize((1024,1024),Image.LANCZOS).save(path)


MASTERS='assets/app_icon'
def export():
    os.makedirs(MASTERS,exist_ok=True)
    shadow,tile,square=(f'{MASTERS}/icon.png',f'{MASTERS}/icon_tile.png',f'{MASTERS}/icon_square.png')
    render(shadow,mode='shadow')   # rounded tile + drop shadow (macOS, Android, web, Linux)
    render(tile,mode='tile')       # rounded tile, no padding (Windows, favicon)
    render(square,mode='square')   # opaque full-bleed square (iOS masks it; web maskable)
    im={k:Image.open(p).convert('RGBA') for k,p in (('shadow',shadow),('tile',tile),('square',square))}
    def save(key,size,path,rgb=False):
        out=im[key].resize((size,size),Image.LANCZOS)
        (out.convert('RGB') if rgb else out).save(path)

    # web / PWA (Icon-512 also feeds the Linux AppImage and Electron builds)
    save('shadow',192,'web/icons/Icon-192.png'); save('shadow',512,'web/icons/Icon-512.png')
    save('square',192,'web/icons/Icon-maskable-192.png'); save('square',512,'web/icons/Icon-maskable-512.png')
    save('tile',32,'web/favicon.png')
    # Android legacy launcher icons
    for d,s in (('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)):
        save('shadow',s,f'android/app/src/main/res/mipmap-{d}/ic_launcher.png')
    # iOS: opaque squares, the OS applies the rounded mask
    ios='ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for e in json.load(open(f'{ios}/Contents.json'))['images']:
        if 'filename' not in e: continue
        pt=float(e['size'].split('x')[0]); sc=int(e['scale'].rstrip('x'))
        save('square',round(pt*sc),f"{ios}/{e['filename']}",rgb=True)
    # macOS: shaped icon with its own shadow
    for s in (16,32,64,128,256,512,1024):
        save('shadow',s,f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{s}.png')
    # Windows
    im['tile'].save('windows/runner/resources/app_icon.ico',sizes=[(s,s) for s in (16,24,32,48,64,128,256)])

if __name__=='__main__':
    export()
