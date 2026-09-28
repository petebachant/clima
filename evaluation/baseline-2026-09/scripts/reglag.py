from series import series
import tomllib,re,csv,statistics
from datetime import date
def P(s):
    p=[int(x) for x in s.strip().split('.')]; return p
def bound(s):
    s=s.strip()
    if s=='*': return (0,0,0),(10**9,0,0)
    if '-' in s:
        a,b=[x.strip() for x in s.split('-')]
    else: a=b=s
    lo=tuple((P(a)+[0,0,0])[:3]); bp=P(b)
    hi=list(bp)+[]; hi[-1]+=1; hi=tuple((hi+[0,0,0])[:3])
    return lo,hi
def inr(spec,v):
    specs=spec if isinstance(spec,list) else [spec]
    return any(bound(s)[0]<=v<bound(s)[1] for s in specs)
def V(s): return tuple(int(x) for x in s.split('.')[:3])
vers=list(csv.DictReader(open("versions.csv")))
regdate={(r['pkg'],r['version']):r['date'] for r in vers}
UP="ClimaCore ClimaComms Thermodynamics CloudMicrophysics SurfaceFluxes ClimaUtilities ClimaParams ClimaTimeSteppers ClimaDiagnostics RRTMGP".split()
out=[]
for d in ["ClimaAtmos","ClimaLand","ClimaCoupler"]:
    C=tomllib.load(open(f"general/C/{d}/Compat.toml","rb"))
    D=[r for r in vers if r['pkg']==d]; D.sort(key=lambda r:r['date'])
    for u in [r for r in vers if r['pkg'] in UP and r['breaking']=='1']:
        SV=[V(x) for x in series(u['pkg'],u['version'])]; hit=None; dependson=False
        for dr in D:
            dv=V(dr['version'])
            for k,tab in C.items():
                if inr(k,dv) and u['pkg'] in tab:
                    dependson=True
                    if any(inr(tab[u['pkg']],x) for x in SV) and dr['date']>=u['date'] and not hit: hit=dr
        if not dependson: continue
        lag=(date.fromisoformat(hit['date'])-date.fromisoformat(u['date'])).days if hit else ''
        out.append(dict(downstream=d,upstream=u['pkg'],version=u['version'],upstream_registered=u['date'],first_downstream_release=hit['version'] if hit else '',downstream_registered=hit['date'] if hit else '',lag_days=lag))
w=csv.DictWriter(open("adoption_lag_registry.csv","w"),fieldnames=list(out[0])); w.writeheader(); w.writerows(out)
for o in out: print(o)
L=[o['lag_days'] for o in out if o['lag_days']!='']
print("n",len(L),"median",statistics.median(L),"mean",round(statistics.mean(L),1),"p75",sorted(L)[int(.75*len(L))],"max",max(L),"never",sum(o['lag_days']=='' for o in out))
for d in ["ClimaAtmos","ClimaLand","ClimaCoupler"]:
    L=[o['lag_days'] for o in out if o['lag_days']!='' and o['downstream']==d]; print(d,len(L),statistics.median(L),max(L), sum(o['lag_days']=='' and o['downstream']==d for o in out))
