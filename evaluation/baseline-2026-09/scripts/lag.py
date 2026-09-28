from series import series
import subprocess,re,csv,tomllib,statistics,json
from datetime import date
def V(s):
    m=re.match(r'(\d+)(?:\.(\d+))?(?:\.(\d+))?',s.strip()); return tuple(int(x) if x else 0 for x in m.groups())
def nparts(s): return len(s.strip().split('.'))
def caret(spec):
    lo=V(spec); n=nparts(spec)
    if lo[0]>0: hi=(lo[0]+1,0,0)
    elif lo[1]>0 or n<2: hi=(0,lo[1]+1,0) if n>=2 else (1,0,0)
    elif n>=3: hi=(0,0,lo[2]+1)
    else: hi=(0,1,0)
    return lo,hi
def admits(spec,v):
    if isinstance(spec,list): spec=','.join(spec)
    v=V(v)
    for part in spec.split(','):
        part=part.strip().lstrip('v')
        if not part or not re.match(r'[\^~=>]*\s*\d',part): print('WARN spec',repr(spec)); continue
        part=part.replace(' ','') if ' - ' not in part else part
        if ' - ' in part:
            a,b=part.split(' - '); lo=V(a); bb=V(b); n=nparts(b)
            hi=(bb[0]+1,0,0) if n==1 else ((bb[0],bb[1]+1,0) if n==2 else (bb[0],bb[1],bb[2]+1))
            if lo<=v<hi: return True; continue
        elif part.startswith('>='):
            if v>=V(part[2:]): return True
        elif part.startswith('='):
            if v==V(part[1:]): return True
        elif part.startswith('~'):
            s=part[1:]; lo=V(s); n=nparts(s)
            hi=(lo[0]+1,0,0) if n==1 else (lo[0],lo[1]+1,0)
            if lo<=v<hi: return True
        else:
            lo,hi=caret(part.lstrip('^'))
            if lo<=v<hi: return True
    return False
UP="ClimaCore ClimaComms Thermodynamics CloudMicrophysics SurfaceFluxes ClimaUtilities ClimaParams ClimaTimeSteppers ClimaDiagnostics RRTMGP".split()
DOWN=["ClimaAtmos","ClimaLand","ClimaCoupler"]
vers=[r for r in csv.DictReader(open("versions.csv")) if r['pkg'] in UP and r['breaking']=='1']
out=[]
for d in DOWN:
    G=f"repos/{d}"
    log=subprocess.run(["git","-C",G,"log","--first-parent","origin/HEAD","--since=2025-06-01","--reverse","--format=%H %cs","--","Project.toml"],capture_output=True,text=True).stdout.split("\n")
    snaps=[]
    for line in filter(None,log):
        h,dt=line.split()
        txt=subprocess.run(["git","-C",G,"show",f"{h}:Project.toml"],capture_output=True,text=True).stdout
        try: t=tomllib.loads(txt)
        except Exception as e: continue
        deps=set(t.get('deps',{}))|set(t.get('weakdeps',{}))
        snaps.append((dt,h,t.get('compat',{}),deps))
    json.dump([(a,b,c,sorted(e)) for a,b,c,e in snaps],open(f"compat_history_{d}.json","w"))
    for r in vers:
        u=r['pkg']
        if not any(u in s[3] for s in snaps): continue
        first=None
        for dt,h,c,deps in snaps:
            if dt< r['date']: continue
            if u in c and any(admits(c[u],x) for x in series(u,r['version'])): first=(dt,h,c[u]); break
        # also check if already admitted at release time (e.g. pre-emptive wide compat)
        pre=[s for s in snaps if s[0]<r['date']]
        if pre and u in pre[-1][2] and any(admits(pre[-1][2][u],x) for x in series(u,r['version'])): first=(r['date'],pre[-1][1],pre[-1][2][u])
        lag=(date.fromisoformat(first[0])-date.fromisoformat(r['date'])).days if first else None
        cens=(date(2026,9,28)-date.fromisoformat(r['date'])).days
        cur=snaps[-1][2].get(u,'')
        out.append(dict(downstream=d,upstream=u,version=r['version'],registered=r['date'],first_admitted=first[0] if first else '',commit=first[1][:10] if first else '',compat_entry=first[2] if first else '',lag_days=lag if lag is not None else '',not_yet_days=cens if lag is None else '',current_compat=cur))
w=csv.DictWriter(open("adoption_lag.csv","w"),fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
for o in out: print(o['downstream'][:9],o['upstream'][:14],o['version'],o['registered'],o['first_admitted'],o['lag_days'],o['not_yet_days'],'|',o['current_compat'])
L=[o['lag_days'] for o in out if o['lag_days']!='']
print("n=",len(L),"median",statistics.median(L),"mean",round(statistics.mean(L),1),"max",max(L),"open",sum(o['lag_days']=='' for o in out))
for d in DOWN:
    L=[o['lag_days'] for o in out if o['lag_days']!='' and o['downstream']==d]
    print(d,len(L),statistics.median(L) if L else None,max(L) if L else None)
