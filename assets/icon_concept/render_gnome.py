"""Flat GNOME/Adwaita-style icon: a screen slab with visible bottom thickness,
showing ChordPro brackets framing lyric lines. Run: python3 render_gnome.py [orange|purple|mono]"""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=3; W=1024*S
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def vgrad(c0,c1):
    g=Image.new('RGB',(1,256))
    for y in range(256): g.putpixel((0,y),lerp(hexc(c0),hexc(c1),y/255))
    return g.resize((W,W),Image.BICUBIC)
def solid(c): return Image.new('RGB',(W,W),hexc(c))
def alpha(m,a): return m.point(lambda v:int(v*a))
def rrect(box,r):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).rounded_rectangle([v*S for v in box],radius=r*S,fill=255); return m
def poly(pts,r=0):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).polygon([(x*S,y*S) for x,y in pts],fill=255)
    return m.filter(ImageFilter.GaussianBlur(r*S)).point(lambda v:255 if v>128 else 0) if r else m
def union(*ms):
    m=ms[0]
    for x in ms[1:]: m=ImageChops.lighter(m,x)
    return m

P={'orange':dict(top='#FFBE6F',bot='#E66100',deep='#9A3A00'),
   'purple':dict(top='#B48CF0',bot='#613583',deep='#3D1F57'),
   'mono':  dict(top='#77767B',bot='#241F31',deep='#000000')}

def render(name):
    pal=P[name]
    img=Image.new('RGBA',(W,W),(0,0,0,0))
    def put(color,m):
        nonlocal img
        layer=(color if isinstance(color,Image.Image) else solid(color)).convert('RGBA'); layer.putalpha(m)
        img=Image.alpha_composite(img,layer)
    X0,Y0,X1,Y1,TH=112,140,912,800,44           # front face + bottom thickness
    body=rrect((X0,Y0,X1,Y1+TH),56)
    # soft drop shadow
    put('#000000',alpha(body.filter(ImageFilter.GaussianBlur(14*S)),0.28))
    # slab: thickness (darker) then face
    put(vgrad('#C0BFBC','#9A9996'),body)
    put(vgrad('#FFFFFF','#EDEBE9'),rrect((X0,Y0,X1,Y1),56))
    # display
    D=(X0+44,Y0+44,X1-44,Y1-44)
    put(vgrad(pal['top'],pal['bot']),rrect(D,18))
    # subtle diagonal glare across the display
    glare=ImageChops.multiply(rrect(D,18),poly([(D[0],D[1]),(620,D[1]),(360,D[3]),(D[0],D[3])]))
    put('#FFFFFF',alpha(glare,0.10))
    # inner shadow at display top edge
    put('#000000',alpha(ImageChops.subtract(rrect(D,18),rrect((D[0],D[1]+6,D[2],D[3]),18)),0.18))
    # brackets: flat white, crisp corners, with a darker 'thickness' lip below
    T=62; ARM=128; by0,by1=250,720
    def br(left):
        x0,x1=(220,220+ARM) if left else (804-ARM,804)
        if left: pts=[(x0,by0),(x1,by0),(x1,by0+T),(x0+T,by0+T),(x0+T,by1-T),(x1,by1-T),(x1,by1),(x0,by1)]
        else:    pts=[(x1,by0),(x0,by0),(x0,by0+T),(x1-T,by0+T),(x1-T,by1-T),(x0,by1-T),(x0,by1),(x1,by1)]
        return poly(pts,3)
    br_m=union(br(True),br(False))
    put(pal['deep'],alpha(ImageChops.offset(br_m,0,10*S),0.35))
    put(vgrad('#FFFFFF','#F0EEEC'),br_m)
    # lyric lines
    lines=union(*[rrect((x0,y,x1,y+34),17) for x0,x1,y in [(352,672,352),(380,644,432),(352,672,512),(404,620,592)]])
    put(pal['deep'],alpha(ImageChops.offset(lines,0,6*S),0.3))
    put('#FFFFFF',lines)
    # crisp highlight along slab top edge
    put('#FFFFFF',alpha(ImageChops.subtract(rrect((X0,Y0,X1,Y1),56),rrect((X0,Y0+3,X1,Y1),56)),0.9))
    img.resize((1024,1024),Image.LANCZOS).save(f'icon_gnome_{name}.png')

for n in (sys.argv[1:] or ['orange']): render(n)
