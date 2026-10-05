import sys,re
rows=[]
for l in open(sys.argv[1]):
    m=re.match(r'frame (\S+) block (\S+),(\S+) ring (\S+),(\S+) err (\S+),(\S+)',l)
    if m: rows.append([float(x) for x in m.groups()])
i=int(sys.argv[2]) if len(sys.argv)>2 else 2  # 1 = x, 2 = y
mov=[(b[0],b[i]-a[i],b[i+4]) for a,b in zip(rows,rows[1:]) if abs(b[i]-a[i])>0.5]
print("frames",len(rows),"moving",len(mov))
if mov:
    e=sorted(abs(m[2]) for m in mov); print("abs err moving: median %.1f p90 %.1f max %.1f"%(e[len(e)//2],e[int(len(e)*.9)],e[-1]))
    l=sorted(abs(m[2]/m[1]) for m in mov if abs(m[1])>3)
    if l: print("lag frames: median %.2f p90 %.2f max %.2f"%(l[len(l)//2],l[int(len(l)*.9)],l[-1]))
print("final err", rows[-1][5:] if rows else None)
