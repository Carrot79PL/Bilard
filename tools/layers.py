# Rasteryzuje warstwy SVG (osobne kształty) do masek w skali podpis_sig.png
import re,numpy as np
from PIL import Image,ImageDraw
SVG='/Users/tomaszmarchewka/Desktop/Claude sandbox/podpis/Tomasz_Marchewka_Studio_czarny (1).svg'
def paths():
    s=open(SVG).read();out=[];grp=None
    for m in re.finditer(r'<g id="([^"]*)"|<path ([^>]*)>',s):
        if m.group(1): grp=m.group(1)
        elif grp!='StudioText': out.append((grp,re.search(r' d="([^"]*)"',' '+m.group(2)).group(1)))
    return out
def polys(d,n=12):
    subs=[];cur=None
    toks=re.findall(r'[MCLZ]|-?\d+\.?\d*',d);i=0;cmd=None
    while i<len(toks):
        t=toks[i]
        if t in 'MCLZ': cmd=t;i+=1
        if cmd=='M': cur=[(float(toks[i]),float(toks[i+1]))];subs.append(cur);i+=2;cmd='L'
        elif cmd=='L': cur.append((float(toks[i]),float(toks[i+1])));i+=2
        elif cmd=='C':
            p0=cur[-1];p1,p2,p3=[(float(toks[i+2*k]),float(toks[i+2*k+1])) for k in range(3)];i+=6
            for k in range(1,n+1):
                u=k/n;a=(1-u)**3;b=3*u*(1-u)**2;c=3*u*u*(1-u);e=u**3
                cur.append((a*p0[0]+b*p1[0]+c*p2[0]+e*p3[0],a*p0[1]+b*p1[1]+c*p2[1]+e*p3[1]))
        elif cmd=='Z': pass
    return subs
def raster(d,sc,ox,oy,W,H):
    acc=np.zeros((H,W),bool)
    for sp in polys(d):
        im=Image.new('1',(W,H),0);ImageDraw.Draw(im).polygon([(x*sc-ox,y*sc-oy) for x,y in sp],fill=1)
        acc^=np.array(im)  # even-odd
    return acc
