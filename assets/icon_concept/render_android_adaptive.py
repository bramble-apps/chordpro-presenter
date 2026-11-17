"""Android adaptive icon layers (launchers cut them into circles, squircles,
squares…): a full-bleed background, the flat ChordPro brackets (as in
render_terminal_style.py) kept inside the safe zone, and a flat monochrome
layer for themed icons. The plain background has no bevel; the
beveled ones (one per launcher shape) are picked in the app.
Run: python3 render_android_adaptive.py  (writes into android/app/src/main/res)"""
import os
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


RES=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','android','app','src','main','res')
SIZES={'mdpi':108,'hdpi':162,'xhdpi':216,'xxhdpi':324,'xxxhdpi':432}

# The safe zone is the middle 66 of the icon's 108: the brackets are scaled
# (K) about the middle to sit inside that circle, whatever shape is cut.
K=0.62
# Scaled about a point picked so the brackets (with their extruded sides,
# 200–778) sit centred in the icon: 550 + (489 − 550)·K ≈ 512.
CX,CY=512,550
def sc(x,y): return (CX+(x-CX)*K, CY+(y-CY)*K)

T=140; ARM=252; Y0,Y1=200,750; DEPTH=28
L0,R1=168,856
def bracket(left):
    if left:
        x0,x1=L0,L0+ARM
        pts=[(x0,Y0),(x1,Y0),(x1,Y0+T),(x0+T,Y0+T),(x0+T,Y1-T),(x1,Y1-T),(x1,Y1),(x0,Y1)]
    else:
        x0,x1=R1-ARM,R1
        pts=[(x1,Y0),(x0,Y0),(x0,Y0+T),(x1-T,Y0+T),(x1-T,Y1-T),(x0,Y1-T),(x0,Y1),(x1,Y1)]
    return poly([sc(x,y) for x,y in pts],5*K)

def layer(src,m,a=1.0):
    out=(src if isinstance(src,Image.Image) else solid(src)).convert('RGBA')
    out.putalpha(alpha(m,a) if a!=1 else m); return out

def save(img,name):
    for d,px in SIZES.items():
        folder=os.path.join(RES,'mipmap-'+d); os.makedirs(folder,exist_ok=True)
        img.resize((px,px),Image.LANCZOS).save(os.path.join(folder,name+'.png'))

full=Image.new('L',(W,W),255)
# Background: the tile's face gradient, full bleed.
bg=layer(fill([(0,'#3D3846'),(0.5,'#2E2A36'),(1,'#241F31')],(0,0,1024,1024)),full)
save(bg,'ic_launcher_background')

# Foreground: shadow + extruded flat brackets on transparent.
top,bot=sc(0,Y0)[1],sc(0,Y1)[1]
b=union(bracket(True),bracket(False))
side=union(*[shift(b,0,d*K) for d in range(0,DEPTH+1,2)])
fg=Image.new('RGBA',(W,W),(0,0,0,0))
fg=Image.alpha_composite(fg,layer('#000000',shift(blur(union(b,side),14*K),0,26*K),0.55))
fg=Image.alpha_composite(fg,layer(fill([(0,'#9A9996'),(1,'#5E5C64')],(0,top,1024,bot+DEPTH*K)),side))
fg=Image.alpha_composite(fg,layer(fill([(0,'#F6F5F4'),(0.55,'#DEDDDA'),(1,'#C0BFBC')],(0,top,1024,bot)),b))
fg=Image.alpha_composite(fg,layer('#FFFFFF',sub(b,shift(b,0,3)),0.9))
fg=Image.alpha_composite(fg,layer('#77767B',mul(b,sub(b,shift(b,0,-2))),0.5))
save(fg,'ic_launcher_foreground')

# Beveled backgrounds, one per launcher shape (chosen in the app's
# Settings → App icon): the desktop tile's look, a dark face on a thicker
# base whose edge shows as a band along the bottom of *that* shape.
V0,V1=1024*18/108,1024*90/108  # what launchers show (the middle 72 of 108)
def shape_mask(kind):
    m=Image.new('L',(W,W),0); d=ImageDraw.Draw(m)
    box=[V0*S,V0*S,V1*S,V1*S]; size=(V1-V0)*S
    if kind=='circle': d.ellipse(box,fill=255)
    elif kind=='square': d.rectangle(box,fill=255)
    elif kind=='rounded': d.rounded_rectangle(box,radius=size*0.22,fill=255)
    else:  # squircle: a superellipse
        import math
        n=4.0; c=(V0+V1)/2*S; r=size/2; pts=[]
        for k in range(720):
            t=2*math.pi*k/720; ct,st=math.cos(t),math.sin(t)
            pts.append((c+r*(abs(ct)**(2/n))*(1 if ct>=0 else -1), c+r*(abs(st)**(2/n))*(1 if st>=0 else -1)))
        d.polygon(pts,fill=255)
    return m

CHIN=54  # the base's band (the desktop tile's, scaled to the shown part)
SHAPES=['circle','squircle','rounded','square']
beveled={}
for kind in SHAPES:
    M=shape_mask(kind)
    face=shift(M,0,-CHIN)
    chin=sub(M,face)
    img=layer(fill([(0,'#3D3846'),(0.5,'#2E2A36'),(1,'#241F31')],(0,V0,1024,V1-CHIN)),full)
    img=Image.alpha_composite(img,layer(fill([(0,'#1E1A26'),(0.85,'#16131C'),(1,'#0C0A10')],(0,V1-CHIN*2,1024,V1)),chin))
    # a faint light rim along the base's bottom edge
    img=Image.alpha_composite(img,layer('#FFFFFF',mul(chin,sub(M,shift(M,0,-4))),0.12))
    # the crisp highlight along the face's top edge
    img=Image.alpha_composite(img,layer('#FFFFFF',mul(face,sub(M,shift(M,0,6))),0.22))
    save(img,'ic_launcher_bg_'+kind)
    beveled[kind]=(img,M)

# Monochrome (Android 13 themed icons): the bracket shapes only.
save(layer('#FFFFFF',union(b,side)),'ic_launcher_monochrome')

# A preview of the shapes launchers cut.
prev=Image.new('RGBA',(4*300+60,340),(240,240,240,255))
icon=Image.alpha_composite(bg,fg).resize((1024,1024),Image.LANCZOS)
cut=[lambda d:d.ellipse((0,0,255,255),fill=255),
     lambda d:d.rounded_rectangle((0,0,255,255),radius=90,fill=255),
     lambda d:d.rounded_rectangle((0,0,255,255),radius=40,fill=255),
     lambda d:d.rectangle((0,0,255,255),fill=255)]
for i,f in enumerate(cut):
    # Launchers show the middle 72 of 108.
    vis=icon.crop((int(1024*18/108),)*2+(int(1024*90/108),)*2).resize((256,256),Image.LANCZOS)
    m=Image.new('L',(256,256),0); f(ImageDraw.Draw(m)); vis.putalpha(m)
    prev.alpha_composite(vis,(30+i*300,30))
prev.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),'android_adaptive_preview.png'))

# The beveled ones, each cut to its own shape.
prev=Image.new('RGBA',(4*300+60,340),(240,240,240,255))
for i,kind in enumerate(SHAPES):
    img,M=beveled[kind]
    full_icon=Image.alpha_composite(img,fg)
    box=(int(V0*S),int(V0*S),int(V1*S),int(V1*S))
    vis=full_icon.crop(box).resize((256,256),Image.LANCZOS)
    vis.putalpha(M.crop(box).resize((256,256),Image.LANCZOS))
    prev.alpha_composite(vis,(30+i*300,30))
prev.save(os.path.join(os.path.dirname(os.path.abspath(__file__)),'android_beveled_preview.png'))
print('ok')
