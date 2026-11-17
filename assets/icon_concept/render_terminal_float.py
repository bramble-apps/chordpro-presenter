"""Terminal-style tile with tilted, floating ChordPro brackets.
The near (right) side is lifted further off the face, so its shadow drops
further and softer than the far (left) side.  Run: python3 render_terminal_float.py"""
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
    img.paste(Image.new('RGB',(W,max(y0,0)),hexc(stops[0][1])),(0,0))
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
def blur(m,r): return m.filter(ImageFilter.GaussianBlur(r*S)) if r>0 else m
def shift(m,dx,dy): return ImageChops.offset(m,int(dx*S),int(dy*S))
def union(*ms):
    m=ms[0]
    for x in ms[1:]: m=ImageChops.lighter(m,x)
    return m

# ---- perspective ----
def solve(A,b):
    n=len(b); M=[r[:]+[b[i]] for i,r in enumerate(A)]
    for c in range(n):
        p=max(range(c,n),key=lambda r:abs(M[r][c])); M[c],M[p]=M[p],M[c]
        for r in range(n):
            if r!=c:
                f=M[r][c]/M[c][c]; M[r]=[M[r][k]-f*M[c][k] for k in range(n+1)]
    return [M[i][n]/M[i][i] for i in range(n)]
def coeffs(dst,src):
    A=[];b=[]
    for (x,y),(u,v) in zip(dst,src):
        A.append([x,y,1,0,0,0,-u*x,-u*y]); b.append(u)
        A.append([0,0,0,x,y,1,-v*x,-v*y]); b.append(v)
    return solve(A,b)

T=140; ARM=252; Y0,Y1=200,750; DEPTH=28; L0,R1=168,856
SRC=[(L0,Y0),(R1,Y0),(R1,Y1),(L0,Y1)]
DST=[(196,252),(856,168),(856,790),(196,708)]       # far left, near right
C=coeffs([(x*S,y*S) for x,y in DST],[(x*S,y*S) for x,y in SRC])
def warp(m): return m.transform((W,W),Image.PERSPECTIVE,C,Image.BICUBIC)

def bracket(left):
    if left:
        x0,x1=L0,L0+ARM
        pts=[(x0,Y0),(x1,Y0),(x1,Y0+T),(x0+T,Y0+T),(x0+T,Y1-T),(x1,Y1-T),(x1,Y1),(x0,Y1)]
    else:
        x0,x1=R1-ARM,R1
        pts=[(x1,Y0),(x0,Y0),(x0,Y0+T),(x1-T,Y0+T),(x1-T,Y1-T),(x0,Y1-T),(x0,Y1),(x1,Y1)]
    return poly(pts,5)

def render(out):
    img=Image.new('RGBA',(W,W),(0,0,0,0))
    def put(src,m,a=1.0):
        nonlocal img
        layer=(src if isinstance(src,Image.Image) else solid(src)).convert('RGBA')
        layer.putalpha(alpha(m,a) if a!=1 else m); img=Image.alpha_composite(img,layer)

    R=228
    tile=rrect((0,0,1023,1023),R)
    put(fill([(0,'#1E1A26'),(0.85,'#16131C'),(1,'#0C0A10')],(0,0,1024,1024)),tile)
    face=rrect((0,0,1023,966),R)
    put(fill([(0,'#4A4554'),(0.5,'#3A3544'),(1,'#2B2638')],(0,0,1024,966)),face)
    put('#FFFFFF',mul(sub(tile,face),sub(tile,shift(tile,0,-3))),0.12)
    put('#FFFFFF',sub(face,shift(face,0,4)),0.22)

    flat=union(bracket(True),bracket(False))
    b=warp(flat)
    side=warp(union(*[shift(flat,0,d) for d in range(0,DEPTH+1,2)]))
    solidm=union(b,side)

    # floating shadow: lift (offset + softness) grows from far-left to near-right
    xl,xr=DST[0][0],DST[1][0]
    shadow=Image.new('L',(W,W),0)
    N=14
    for i in range(N):
        t=(i+0.5)/N
        dx,dy,r,a=6+34*t, 20+80*t, 6+26*t, 0.95-0.2*t
        sh=alpha(shift(blur(solidm,r),dx,dy),a)
        x0=int((xl-40+(xr-xl+120)*i/N)*S); x1=int((xl-40+(xr-xl+120)*(i+1)/N)*S)
        if i==0: x0=0
        if i==N-1: x1=W
        strip=Image.new('L',(W,W),0); strip.paste(sh.crop((x0,0,x1,W)),(x0,0))
        shadow=ImageChops.lighter(shadow,strip)
    shadow=blur(shadow,3)               # hide strip seams
    put('#0A0810',mul(shadow,face))

    # extrusion + front face + bevels (same treatment as the flat version)
    put(fill([(0,'#9A9996'),(1,'#5E5C64')],(0,160,1024,830)),side)
    put(fill([(0,'#F6F5F4'),(0.55,'#DEDDDA'),(1,'#C0BFBC')],(0,168,1024,790)),b)
    put('#FFFFFF',sub(b,shift(b,0,4)),0.9)
    put('#77767B',mul(b,sub(b,shift(b,0,-3))),0.5)

    # exterior drop shadow on padded canvas
    PAD=72; size=W-2*PAD*S
    icon=img.resize((size,size),Image.LANCZOS); a=icon.getchannel('A')
    canvas=Image.new('RGBA',(W,W),(0,0,0,0))
    sh=Image.new('L',(W,W),0); sh.paste(a,(PAD*S,PAD*S+18*S))
    canvas.putalpha(sh.filter(ImageFilter.GaussianBlur(22*S)).point(lambda v:int(v*0.45)))
    tight=Image.new('L',(W,W),0); tight.paste(a,(PAD*S,PAD*S+5*S))
    t2=Image.new('RGBA',(W,W),(0,0,0,0)); t2.putalpha(tight.filter(ImageFilter.GaussianBlur(4*S)).point(lambda v:int(v*0.35)))
    canvas=Image.alpha_composite(canvas,t2)
    canvas.alpha_composite(icon,(PAD*S,PAD*S))
    canvas.resize((1024,1024),Image.LANCZOS).save(out)

render('icon_terminal_float.png')
