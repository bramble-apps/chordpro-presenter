"""Skeuomorphic GNOME-style icon concepts for ChordPro Presenter.
Run: python3 render_gnome_variants.py   -> icon_gnome_screen.png, icon_gnome_sheet.png, icon_gnome_monitor.png"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageFont
S=3; W=1024*S
FONT='/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf'
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def grad(stops,horiz=False):
    g=Image.new('RGB',(256,1) if horiz else (1,256))
    for k in range(256):
        t=k/255
        for i in range(len(stops)-1):
            (p0,c0),(p1,c1)=stops[i],stops[i+1]
            if p0<=t<=p1:
                g.putpixel((k,0) if horiz else (0,k),lerp(hexc(c0),hexc(c1),(t-p0)/max(p1-p0,1e-6))); break
    return g
def fill(stops,box,horiz=False):
    """gradient spanning only box (x0,y0,x1,y1) in icon units"""
    x0,y0,x1,y1=[int(v*S) for v in box]
    img=Image.new('RGB',(W,W),hexc(stops[-1][1]))
    img.paste(grad(stops,horiz).resize((x1-x0,y1-y0),Image.BICUBIC),(x0,y0))
    if not horiz:
        img.paste(Image.new('RGB',(W,y0),hexc(stops[0][1])),(0,0))
    return img
def solid(c): return Image.new('RGB',(W,W),hexc(c))
def alpha(m,a): return m.point(lambda v:int(v*a))
def rrect(box,r):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).rounded_rectangle([v*S for v in box],radius=r*S,fill=255); return m
def ellipse(box):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).ellipse([v*S for v in box],fill=255); return m
def poly(pts,r=0):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).polygon([(x*S,y*S) for x,y in pts],fill=255)
    return m.filter(ImageFilter.GaussianBlur(r*S)).point(lambda v:255 if v>128 else 0) if r else m
def text(s,x,y,size,anchor='ls'):
    m=Image.new('L',(W,W),0); ImageDraw.Draw(m).text((x*S,y*S),s,fill=255,font=ImageFont.truetype(FONT,int(size*S)),anchor=anchor); return m
def union(*ms):
    m=ms[0]
    for x in ms[1:]: m=ImageChops.lighter(m,x)
    return m
def sub(a,b): return ImageChops.subtract(a,b)
def mul(a,b): return ImageChops.multiply(a,b)
def blur(m,r): return m.filter(ImageFilter.GaussianBlur(r*S))
def shift(m,dx,dy): return ImageChops.offset(m,int(dx*S),int(dy*S))

class Canvas:
    def __init__(s): s.img=Image.new('RGBA',(W,W),(0,0,0,0))
    def put(s,src,m,a=1.0):
        layer=(src if isinstance(src,Image.Image) else solid(src)).convert('RGBA')
        layer.putalpha(alpha(m,a) if a!=1 else m)
        s.img=Image.alpha_composite(s.img,layer)
    def shadow(s,m,dy=10,r=12,a=0.3): s.put('#000000',shift(blur(m,r),0,dy),a)
    def save(s,f): s.img.resize((1024,1024),Image.LANCZOS).save(f)

ORANGE=[(0,'#FFA348'),(1,'#E66100')]
def chord_row(c,x0,y,chords,line_w,ink='#3D3846',accent='#E66100',size=54):
    """'[G]' chord tags in accent colour above a lyric bar"""
    for cx,name in chords:
        c.put(accent,text(f'[{name}]',cx,y,size))
    c.put(ink,rrect((x0,y+22,x0+line_w,y+50),14))

# ---------- 1. pull-down projector screen ----------
def screen():
    c=Canvas()
    scr=(170,206,854,800)
    # screen sheet
    sheet=rrect(scr,6)
    c.shadow(sheet,14,16,0.28)
    c.put(fill([(0,'#FFFFFF'),(1,'#EAE8E5')],scr),sheet)
    # thin black masking border, like a real projection screen
    c.put('#241F31',sub(sheet,rrect((scr[0]+18,scr[1]+30,scr[2]-18,scr[3]-40),4)),0.9)
    # shadow cast by roller onto top of sheet
    c.put('#000000',mul(sheet,fill([(0,'#FFFFFF'),(0.08,'#000000'),(1,'#000000')],scr).convert('L')),0.35)
    # projected lyrics with chords
    chord_row(c,262,330,[(262,'G'),(560,'D')],500)
    chord_row(c,262,470,[(262,'Em'),(600,'C')],420)
    chord_row(c,262,610,[(262,'G'),(470,'D'),(680,'G')],480)
    # weighted bottom bar + pull cord
    bar=rrect((150,782,874,820),19)
    c.shadow(bar,6,6,0.3)
    c.put(fill([(0,'#9A9996'),(0.45,'#5E5C64'),(1,'#3D3846')],(150,782,874,820)),bar)
    c.put('#FFFFFF',sub(bar,shift(bar,0,4)),0.35)
    c.put('#5E5C64',rrect((506,816,518,872),6))
    ring=sub(ellipse((476,862,548,934)),ellipse((494,880,530,916)))
    c.shadow(ring,4,4,0.3); c.put(fill([(0,'#DEDDDA'),(1,'#77767B')],(476,862,548,934)),ring)
    # roller housing (metal cylinder) with end caps
    tube=rrect((116,140,908,232),46)
    c.shadow(tube,10,12,0.35)
    c.put(fill([(0,'#F6F5F4'),(0.25,'#FFFFFF'),(0.55,'#C0BFBC'),(0.8,'#9A9996'),(1,'#77767B')],(116,140,908,232)),tube)
    c.put('#FFFFFF',sub(tube,shift(tube,0,5)),0.8)
    for x0,x1 in ((116,176),(848,908)):
        cap=rrect((x0,136,x1,236),24)
        c.put(fill([(0,'#FFA348'),(0.4,'#F57C1F'),(1,'#C64600')],(x0,136,x1,236)),cap)
        c.put('#FFFFFF',sub(cap,shift(cap,0,5)),0.6)
    c.save('icon_gnome_screen.png')

# ---------- 2. song sheet + guitar pick ----------
def sheet():
    c=Canvas()
    P=(176,96,780,904); fold=120
    page=poly([(P[0],P[1]),(P[2]-fold,P[1]),(P[2],P[1]+fold),(P[2],P[3]),(P[0],P[3])],4)
    thick=shift(page,0,10)
    c.shadow(union(page,thick),18,18,0.3)
    c.put('#C0BFBC',thick)
    c.put(fill([(0,'#FFFFFF'),(1,'#F0EEEC')],P),page)
    # dog-ear
    ear=poly([(P[2]-fold,P[1]),(P[2]-fold,P[1]+fold),(P[2],P[1]+fold)],2)
    c.shadow(ear,4,6,0.25)
    c.put(fill([(0,'#DEDDDA'),(1,'#FFFFFF')],(P[2]-fold,P[1],P[2],P[1]+fold)),ear)
    # title block: "{title}" directive feel
    c.put('#241F31',rrect((246,176,560,216),20))
    c.put('#9A9996',rrect((246,236,440,256),10))
    chord_row(c,246,360,[(246,'C'),(490,'Am')],440)
    chord_row(c,246,484,[(246,'F'),(430,'G')],380)
    chord_row(c,246,608,[(246,'C'),(520,'G')],460)
    chord_row(c,246,732,[(246,'Am')],250)
    # guitar pick
    cx,cy,ang=752,756,-24
    pts=[]
    for t,(rx,ry) in [(0,(-160,-90)),(0,(-110,-150)),(0,(110,-150)),(0,(160,-90)),(0,(26,170)),(0,(-26,170))]:
        a=math.radians(ang); pts.append((cx+rx*math.cos(a)-ry*math.sin(a),cy+rx*math.sin(a)+ry*math.cos(a)))
    pick=poly(pts,24)
    edge=shift(pick,0,12)
    c.shadow(union(pick,edge),18,20,0.35)
    c.put('#9C3E00',edge)
    box=(cx-170,cy-170,cx+170,cy+190)
    c.put(fill([(0,'#FFBE6F'),(0.5,'#FF7800'),(1,'#C64600')],box),pick)
    # glossy highlight + engraved bracket mark
    hl=mul(pick,ellipse((cx-170,cy-190,cx+60,cy-40)))
    c.put('#FFFFFF',blur(hl,8),0.35)
    mark=text('[ ]',cx,cy-10,110,'mm').rotate(-ang,center=(cx*S,(cy-10)*S),resample=Image.BICUBIC)
    c.put('#7A2E00',shift(mark,0,-3),0.45); c.put('#FFD8A8',mark,0.85)
    c.put('#FFFFFF',sub(pick,shift(pick,0,5)),0.5)
    c.save('icon_gnome_sheet.png')

# ---------- 3. stage monitor ----------
def monitor():
    c=Canvas()
    # stand
    neck=poly([(462,700),(562,700),(586,850),(438,850)])
    c.put(fill([(0,'#5E5C64'),(1,'#9A9996')],(438,700,586,850),True),neck)
    c.put(fill([(0,'#77767B'),(0.5,'#DEDDDA'),(1,'#77767B')],(438,700,586,850),True),neck,0.7)
    base=rrect((292,836,732,890),27)
    c.shadow(base,8,10,0.35)
    c.put(fill([(0,'#F6F5F4'),(0.5,'#C0BFBC'),(1,'#77767B')],(292,836,732,890)),base)
    c.put('#FFFFFF',sub(base,shift(base,0,4)),0.8)
    # body: bezel with bottom thickness
    B=(96,150,928,722)
    body=rrect(B,40); side=shift(body,0,16)
    c.shadow(union(body,side),20,22,0.35)
    c.put('#1E1A26',side)
    c.put(fill([(0,'#5E5C64'),(0.06,'#3D3846'),(1,'#241F31')],B),body)
    c.put('#FFFFFF',sub(body,shift(body,0,4)),0.5)
    # display
    D=(132,186,892,666)
    disp=rrect(D,14)
    c.put(fill([(0,'#2A2638'),(1,'#0E0C14')],D),disp)
    # content: orange chord brackets + white lyrics (big & readable like a confidence monitor)
    for y,ch,w in ((300,[(196,'G'),(520,'D')],560),(440,[(196,'Em'),(560,'C')],470),(580,[(196,'G'),(420,'D')],520)):
        chord_row(c,196,y,ch,w,ink='#F6F5F4',accent='#FFA348',size=60)
    # glass reflection
    c.put('#FFFFFF',mul(disp,poly([(D[0],D[1]),(560,D[1]),(300,D[3]),(D[0],D[3])])),0.07)
    # power LED
    c.put('#FFA348',ellipse((503,688,521,706)))
    c.put('#FFBE6F',blur(ellipse((503,688,521,706)),6),0.8)
    c.save('icon_gnome_monitor.png')

screen(); sheet(); monitor()
