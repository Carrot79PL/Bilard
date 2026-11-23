import numpy as np, heapq, json, sys
from PIL import Image
R='/Users/tomaszmarchewka/Desktop/Claude sandbox/Bilard/Resources/'
al=np.array(Image.open(R+'podpis_sig.png'))[...,3]
ink=al>110
H,W=ink.shape
def zs(img):
    im=img.copy()
    while True:
        ch=False
        for step in (0,1):
            p=np.pad(im,1)
            P2=p[:-2,1:-1];P3=p[:-2,2:];P4=p[1:-1,2:];P5=p[2:,2:];P6=p[2:,1:-1];P7=p[2:,:-2];P8=p[1:-1,:-2];P9=p[:-2,:-2]
            nb=[P2,P3,P4,P5,P6,P7,P8,P9]
            B=sum(x.astype(np.int8) for x in nb)
            seq=nb+[P2]
            A=sum(((~seq[i])&seq[i+1]).astype(np.int8) for i in range(8))
            if step==0: c=~(P2&P4&P6)&~(P4&P6&P8)
            else: c=~(P2&P4&P8)&~(P2&P6&P8)
            m=im&(B>=2)&(B<=6)&(A==1)&c
            if m.any(): im=im&~m; ch=True
        if not ch: break
    return im
sk=zs(ink)
ys,xs=np.nonzero(sk); print('skel',len(xs))
pts=set(zip(ys.tolist(),xs.tolist()))
N8=[(-1,-1),(-1,0),(-1,1),(0,-1),(0,1),(1,-1),(1,0),(1,1)]
# components
comp={};comps=[]
for p in pts:
    if p in comp: continue
    st=[p];comp[p]=len(comps);lst=[p]
    while st:
        y,x=st.pop()
        for dy,dx in N8:
            q=(y+dy,x+dx)
            if q in pts and q not in comp: comp[q]=len(comps);st.append(q);lst.append(q)
    comps.append(lst)
big=max(comps,key=lambda c:max(p[1] for p in c)-min(p[1] for p in c))
U0=[p for p in big if p[0]>440 and abs(p[1]-1240)>70]
co=np.polyfit([p[1] for p in U0],[p[0] for p in U0],4)
ulset=set(p for p in big if abs(p[0]-np.polyval(co,p[1]))<16 and p[0]>400 and abs(p[1]-1241)>14)
print('ulset',len(ulset))
rest=pts-ulset
def split(S):
    seen=set();out=[]
    for p in S:
        if p in seen: continue
        st=[p];seen.add(p);lst=[p]
        while st:
            y,x=st.pop()
            for dy,dx in N8:
                q=(y+dy,x+dx)
                if q in S and q not in seen: seen.add(q);st.append(q);lst.append(q)
        out.append(lst)
    return [c for c in out if len(c)>=15]
cr=split(rest);cu=split(ulset)
comps=cr+cu;isul=[False]*len(cr)+[True]*len(cu)
for i,c in enumerate(comps):
    if min(p[0] for p in c)>440 and max(p[1] for p in c)-min(p[1] for p in c)>60: isul[i]=True
curl=[i for i,c in enumerate(comps) if isul[i] and min(p[1] for p in c)>1900 and max(p[0] for p in c)>515 and max(p[1] for p in c)>2100 and min(p[0] for p in c)>515]
info=[]
for i,c in enumerate(comps):
    yy=[p[0] for p in c];xx=[p[1] for p in c];info.append((min(xx),max(xx),min(yy),max(yy),len(c)));print(i,isul[i],info[-1])
order=sorted([i for i in range(len(comps)) if not isul[i]],key=lambda i:info[i][0])+sorted([i for i in range(len(comps)) if isul[i]],key=lambda i:(info[i][0]+(5000 if info[i][2]>515 and info[i][0]>1900 and info[i][1]<2140 else 0)))
ul=-1
def dijk(c,start,pen):
    s=set(c);d={start:0.0};h=[(0.0,start)]
    while h:
        dd,p=heapq.heappop(h)
        if dd>d[p]:continue
        for dy,dx in N8:
            q=(p[0]+dy,p[1]+dx)
            if q in s:
                cost=(1.414 if dy and dx else 1.0)*(pen if dx<0 else 1.0)
                nd=dd+cost
                if nd<d.get(q,1e18): d[q]=nd;heapq.heappush(h,(nd,q))
    return d
GAP=40.0
tmap=np.full((H,W),np.nan,np.float32)
t0=0.0;tip=[]
allt={}
for i in order:
    c=comps[i]
    cs=set(c)
    ends=[p for p in c if sum(((p[0]+dy,p[1]+dx) in cs) for dy,dx in N8)==1]
    start=min(ends or c,key=lambda p:p[0]) if (info[i][1]-info[i][0]<40) else (max if (info[i][2]>515 and info[i][0]>1900 and info[i][1]<2140) else min)(ends or c,key=lambda p:p[1])
    d=dijk(c,start,3.0)
    # unreachable none (same comp). time
    mx=max(d.values())
    for p,v in d.items(): allt[p]=t0+v
    t0+=mx+GAP
total=t0-GAP
print('total path',total)
keys=np.array(list(allt.keys()));vals=np.array([allt[k] for k in allt],np.float32)/total
tm=np.full((H,W),-1.0,np.float32);tm[keys[:,0],keys[:,1]]=vals
ulpix=np.zeros((H,W),bool)
for i,c in enumerate(comps):
    if isul[i]:
        for (y,x) in c: ulpix[y,x]=True
m=ulpix.copy()
for _ in range(17):
    p=np.pad(m,1);m=m|p[:-2,1:-1]|p[2:,1:-1]|p[1:-1,:-2]|p[1:-1,2:]|p[:-2,:-2]|p[2:,2:]|p[:-2,2:]|p[2:,:-2]
maskul=m&ink
maskul[:,1225:1258]=False
tu=np.where(ulpix,tm,-1.0).astype(np.float32)
for it in range(40):
    p=np.pad(tu,1,constant_values=-1);best=np.full((H,W),-1.0,np.float32)
    for dy,dx in N8:
        sh=p[1+dy:1+dy+H,1+dx:1+dx+W];best=np.where((best<0)&(sh>=0),sh,best)
    upd=maskul&(tu<0)&(best>=0)
    if not upd.any():break
    tu[upd]=best[upd]
tm=np.where(maskul&(tu>=0),tu,tm)
tu_ul=tu.copy()
known=tm>=0
for it in range(80):
    need=ink&~known
    if not need.any():break
    p=np.pad(tm,1,constant_values=-1)
    best=np.full((H,W),-1.0,np.float32)
    for dy,dx in N8:
        sh=p[1+dy:1+dy+H,1+dx:1+dx+W]
        best=np.where((best<0)&(sh>=0),sh,best)
    upd=need&(best>=0);tm[upd]=best[upd];known=tm>=0
# stem fix: in crossing band use stem time interpolated by y
ulpts=set(q for i,c in enumerate(comps) if isul[i] for q in c)
sy={}
for (y,x),v in allt.items():
    if 1200<=x<=1285 and 250<y<700 and (y,x) not in ulpts: sy.setdefault(y,[]).append(v/total)
yy=np.array(sorted(sy));tt=np.array([np.median(sy[k]) for k in yy])
tt=np.maximum.accumulate(tt)
# warstwy SVG: imie i nazwisko (warstwy 1..6) PRZED podkresleniem (warstwa 0, razem z ogonem lodygi M)
sys.path.insert(0,R+'../tools');from layers import paths,raster
LP=paths();LM=[raster(d,0.6934,55,55.6,W,H) for g,d in LP]
Lr=np.zeros((H,W),bool)
for m_ in LM[1:]: Lr|=m_
q=np.pad(Lr,1);Lr=Lr|q[:-2,1:-1]|q[2:,1:-1]|q[1:-1,:-2]|q[1:-1,2:]
by,bx=np.nonzero(ink[:,1215:1270]&Lr[:,1215:1270]);bx=bx+1215
tm[by,bx]=np.interp(by,yy,tt)
only0=ink&~Lr
tm[only0]=-1
src=np.where(ulpix&~Lr,tu_ul,-1.0).astype(np.float32)
src=np.where(only0,src,-1.0)
for it in range(400):
    need=only0&(src<0)
    if not need.any():break
    p=np.pad(src,1,constant_values=-1);best=np.full((H,W),-1.0,np.float32)
    for dy,dx in N8:
        sh=p[1+dy:1+dy+H,1+dx:1+dx+W];best=np.where((best<0)&(sh>=0),sh,best)
    upd=need&(best>=0)
    if not upd.any():break
    src[upd]=best[upd]
tm=np.where(only0&(src>=0),src,tm)
# podkreslenie nie moze zaczac sie przed koncem nazwiska
tl=tm[Lr&ink].max();tu0=tm[only0&(tm>=0)].min();print('name end',tl,'underline start',tu0)
tm=np.where(only0&(tm>=0),np.maximum(tm,tl+0.004),tm)
tm[~ink]=0;tm=np.clip(tm,0,1)
# anti-alias edge pixels (alpha 1..110) copy nearest: dilate once more
amask=al>0
for _ in range(6):
    p=np.pad(amask,1);amask=amask|p[:-2,1:-1]|p[2:,1:-1]|p[1:-1,:-2]|p[1:-1,2:]
for it in range(14):
    need=amask&(tm==0)&~ink
    p=np.pad(tm,1);best=np.zeros((H,W),np.float32)
    for dy,dx in N8:
        sh=p[1+dy:1+dy+H,1+dx:1+dx+W];best=np.where((best==0)&(sh>0),sh,best)
    tm=np.where(need&(best>0),best,tm)
v=np.where(amask,np.round(tm*65000).astype(np.uint32)+500,0).astype(np.uint32)
rgb=np.zeros((H,W,3),np.uint8);rgb[...,0]=v>>8;rgb[...,1]=v&255
Image.fromarray(rgb).save(R+'podpis_time.png')
# tip track z finalnej mapy czasu
NB=400;track=[];last=(0,0)
ty,tx=np.nonzero(ink&(tm>0));tv=tm[ty,tx]
for b in range(NB+1):
    t=b/NB;m=(np.abs(tv-t)<1.2/NB)
    if m.any(): last=(float(tx[m].mean())/W,float(ty[m].mean())/H)
    track.append(last)
json.dump({'tip':track,'total':total},open(R+'podpis_pen.json','w'))
# debug picture
dbg=np.zeros((H,W,3),np.uint8)
import colorsys
cm=np.array([[int(255*c) for c in colorsys.hsv_to_rgb(0.7*(1-i/255),1,1)] for i in range(256)],np.uint8)
dbg=cm[np.clip((tm*255).astype(int),0,255)]*(ink[...,None])
Image.fromarray(dbg).resize((1200,440)).save('/tmp/bshots/timedbg.png')
