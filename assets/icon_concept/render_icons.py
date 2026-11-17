import sys
from PIL import Image, ImageDraw, ImageFilter, ImageChops
S=2; W=1024*S
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def vgrad(stops):
    g=Image.new('RGB',(1,256))
    for y in range(256):
        t=y/255
        for i in range(len(stops)-1):
            (p0,c0),(p1,c1)=stops[i],stops[i+1]
            if p0<=t<=p1: g.putpixel((0,y),lerp(hexc(c0),hexc(c1),(t-p0)/(p1-p0))); break
    return g.resize((W,W),Image.BICUBIC)
def solid(c): return Image.new('RGB',(W,W),hexc(c))
def alpha(m,a): return m.point(lambda v:int(v*a))
def rrect(box,r):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).rounded_rectangle([v*S for v in box],radius=r*S,fill=255); return m
def blur(m,r): return m.filter(ImageFilter.GaussianBlur(r*S))
def shift(m,dx,dy): return ImageChops.offset(m,int(dx*S),int(dy*S))
def sub(a,b): return ImageChops.subtract(a,b)
def mul(a,b): return ImageChops.multiply(a,b)
def union(*ms):
    m=ms[0]
    for x in ms[1:]: m=ImageChops.lighter(m,x)
    return m

# ---- perspective (Windows-8 style tilt: left edge recedes) ----
def solve(A,b):
    n=len(b); M=[r[:]+[b[i]] for i,r in enumerate(A)]
    for c in range(n):
        p=max(range(c,n),key=lambda r:abs(M[r][c])); M[c],M[p]=M[p],M[c]
        for r in range(n):
            if r!=c:
                f=M[r][c]/M[c][c]; M[r]=[M[r][k]-f*M[c][k] for k in range(n+1)]
    return [M[i][n]/M[i][i] for i in range(n)]
def coeffs(dst,src):  # maps output(dst) -> input(src) for PIL
    A=[];b=[]
    for (x,y),(u,v) in zip(dst,src):
        A.append([x,y,1,0,0,0,-u*x,-u*y]); b.append(u)
        A.append([0,0,0,x,y,1,-v*x,-v*y]); b.append(v)
    return solve(A,b)
FX0,FY0,FX1,FY1=222,196,802,828                       # flat group bounds (squarer)
SRC=[(FX0,FY0),(FX1,FY0),(FX1,FY1),(FX0,FY1)]
DST=[(214,250),(812,170),(812,856),(214,776)]          # tilted quad (gentler tilt)
C=coeffs([(x*S,y*S) for x,y in DST],[(x*S,y*S) for x,y in SRC])
def warp(m): return m.transform((W,W),Image.PERSPECTIVE,C,Image.BICUBIC)

T=104; ARM=168   # bracket thickness / arm length
def bracket(left):
    m=Image.new('L',(W,W),0); d=ImageDraw.Draw(m)
    if left: pts=[(FX0,FY0),(FX0+ARM,FY0),(FX0+ARM,FY0+T),(FX0+T,FY0+T),(FX0+T,FY1-T),(FX0+ARM,FY1-T),(FX0+ARM,FY1),(FX0,FY1)]
    else:    pts=[(FX1,FY0),(FX1-ARM,FY0),(FX1-ARM,FY0+T),(FX1-T,FY0+T),(FX1-T,FY1-T),(FX1-ARM,FY1-T),(FX1-ARM,FY1),(FX1,FY1)]
    d.polygon([(x*S,y*S) for x,y in pts],fill=255)
    m=blur(m,6).point(lambda v:255 if v>128 else 0)   # round all corners
    return warp(blur(m,0.7))

def edge(m,w=3):
    inner=blur(m,w).point(lambda v:255 if v>250 else 0)
    return sub(m,inner)

def glass(img,m,pal,frost,tint_a,rim_a):
    # frosted: heavy blur of what's behind, lifted toward white and tinted
    fr=img.filter(ImageFilter.GaussianBlur(28*S))
    fr=Image.blend(fr,solid('#FFFFFF'),frost)
    fr=Image.blend(fr,solid(pal['tint']),tint_a)
    img=Image.composite(fr,img,m)
    # subtle frosted noise-free sheen: brighter at top
    img=Image.composite(solid('#FFFFFF'),img,mul(m,alpha(vgrad([(0,'#FFFFFF'),(0.6,'#000000'),(1,'#000000')]).convert('L'),0.3)))
    # inner soft glow along the edges (thick glass refraction)
    ig=mul(m,sub(m,blur(m,10)).point(lambda v:min(255,v*2)))
    img=Image.composite(solid('#FFFFFF'),img,alpha(ig,0.4))
    # rims: thin bright all round, stronger on top-left, darker on bottom-right
    img=Image.composite(solid('#FFFFFF'),img,alpha(edge(m,2),rim_a))
    img=Image.composite(solid('#FFFFFF'),img,alpha(blur(mul(m,sub(m,shift(m,4,7))),1.5),0.85))
    img=Image.composite(solid(pal['deep']),img,alpha(blur(mul(m,sub(m,shift(m,-3,-6))),2),0.35))
    return img

def render(pal,out):
    img=vgrad(pal['bg'])
    tile=rrect((0,0,1023,1023),228)
    g=Image.new('L',(W,W),0); ImageDraw.Draw(g).ellipse([-200*S,-520*S,1224*S,420*S],fill=255)
    img=Image.composite(solid('#FFFFFF'),img,alpha(blur(g,120),pal['glow']))
    rim=sub(tile,rrect((10,10,1013,1013),220))
    img=Image.composite(solid('#FFFFFF'),img,alpha(blur(sub(rim,shift(tile,0,40)),3),0.55))
    img=Image.composite(solid('#000000'),img,alpha(blur(sub(rim,shift(tile,0,-40)),4),0.25))

    scr=warp(rrect((FX0+60,FY0+56,FX1-60,FY1-56),14))
    bL,bR=bracket(True),bracket(False)
    allm=union(scr,bL,bR)
    img=Image.composite(solid(pal['deep']),img,alpha(shift(blur(allm,30),10,30),0.3))

    img=glass(img,scr,pal,frost=0.30,tint_a=0.10,rim_a=0.7)
    lines=Image.new('L',(W,W),0)
    for (x0,x1,y) in [(372,652,405),(392,632,477),(372,652,549),(412,612,621)]:
        lines=union(lines,rrect((x0,y,x1,y+34),17))
    lines=warp(lines)
    img=Image.composite(solid(pal['deep']),img,alpha(shift(blur(lines,4),0,4),0.25))
    img=Image.composite(solid('#FFFFFF'),img,alpha(lines,0.92))

    for m in (bL,bR):
        img=Image.composite(solid(pal['deep']),img,alpha(shift(blur(m,10),4,12),0.35))
        img=glass(img,m,pal,frost=0.42,tint_a=0.16,rim_a=0.95)

    o=img.convert('RGBA'); o.putalpha(tile)
    o.resize((1024,1024),Image.LANCZOS).save(out)

P={
 'orange':dict(bg=[(0,'#FFC24D'),(0.5,'#FF8A26'),(1,'#E2481B')],glow=0.25,deep='#7A2300',tint='#FFD070'),
 'purple':dict(bg=[(0,'#A97CFF'),(0.5,'#6A3DE8'),(1,'#2E1478')],glow=0.22,deep='#16063F',tint='#C9A8FF'),
 'mono':  dict(bg=[(0,'#6A6A6E'),(0.5,'#3A3A3E'),(1,'#141416')],glow=0.18,deep='#000000',tint='#B4B4BA'),
}
for name in sys.argv[1:]: render(P[name],f'icon_{name}.png')
