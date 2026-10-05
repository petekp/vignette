import sys
from PIL import Image
im=Image.open(sys.argv[1]).convert('RGB'); w,h=im.size; px=im.load()
xs=[];ys=[];ms=[];ns=[]; cs=[];ds=[]
for y in range(0,h):
    for x in range(0,w):
        r,g,b=px[x,y]
        if g>200 and r<90 and b<90: xs.append(x); ys.append(y)
        elif r>200 and b>200 and g<80: ms.append(x); ns.append(y)
        elif b>200 and g>160 and r<60: cs.append(x); ds.append(y)
c=lambda a,b:"%.1f,%.1f"%(sum(a)/len(a),sum(b)/len(b)) if a else "none"
print("green",c(xs,ys),"magenta",c(ms,ns),"cyan",c(cs,ds))
