import re
def _V(s): return tuple(int(x) for x in re.match(r'(\d+)\.(\d+)\.(\d+)',s).groups())
def series(pkg,ver):
    t=open(f"general/{pkg[0]}/{pkg}/Versions.toml").read()
    allv=re.findall(r'^\["([^"]+)"\]',t,re.M); v=_V(ver)
    key=(lambda x:x[:1]) if v[0]>0 else (lambda x:x[:2])
    return sorted([x for x in allv if key(_V(x))==key(v)],key=_V)
