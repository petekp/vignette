import sys,re
rows=[]
for l in open(sys.argv[1]):
    m=re.match(r'frame (\S+) block (\S+),(\S+) ring (\S+),(\S+) err (\S+),(\S+)',l)
    if m: rows.append([float(x) for x in m.groups()])
moving=[]
for a,b in zip(rows,rows[1:]):
    dt=b[0]-a[0]; v=(b[1]-a[1])
    if abs(v)>0.5: moving.append((b[0],v,dt,b[5]))
print("frames",len(rows),"moving",len(moving))
if moving:
    errs=sorted(abs(m[3]) for m in moving)
    print("abs x err while moving: median %.1f p90 %.1f max %.1f pt"%(errs[len(errs)//2],errs[int(len(errs)*.9)],errs[-1]))
    # lag in frames = err / block step per frame
    lags=sorted(abs(m[3]/m[1]) for m in moving if abs(m[1])>3)
    if lags: print("lag in frames (err/step): median %.2f p90 %.2f max %.2f"%(lags[len(lags)//2],lags[int(len(lags)*.9)],lags[-1]))
    dts=sorted(m[2] for m in moving); print("frame interval median %.1f ms"%(dts[len(dts)//2]*1000))
still=[abs(r[5]) for r in rows]
print("max abs err overall %.1f"%max(still))
