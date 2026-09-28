import tomllib,json,csv,re,statistics
from datetime import datetime,timezone
def _P(x): return [int(y) for y in x.strip().split('.')]
def bound(x):
    x=x.strip()
    if x=='*': return (0,0,0),(10**9,0,0)
    a,b=[y.strip() for y in x.split('-')] if '-' in x else (x,x)
    lo=tuple((_P(a)+[0,0,0])[:3]); hi=_P(b); hi[-1]+=1; return lo,tuple((hi+[0,0,0])[:3])
def inr(spec,v):
    return any(bound(x)[0]<=v<bound(x)[1] for x in (spec if isinstance(spec,list) else [spec]))
SET="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
UP="ClimaComms ClimaCore Thermodynamics CloudMicrophysics SurfaceFluxes ClimaUtilities ClimaParams ClimaTimeSteppers ClimaDiagnostics RRTMGP RootSolvers Insolation".split()
SINKS=["ClimaAtmos","ClimaLand","ClimaCoupler"]
def V(s): return tuple(int(x) for x in s.split('.')[:3])
def D(s): return datetime.fromisoformat(s).astimezone(timezone.utc)
OLD=D("1970-01-01T00:00:00+00:00")
import subprocess
def regdates(pkg):
    out=subprocess.run(["git","-C","general","log","--format=COMMIT %cI","-p","--",f"{pkg[0]}/{pkg}/Versions.toml"],capture_output=True,text=True).stdout
    dt=None; r={}
    for l in out.splitlines():
        if l.startswith("COMMIT "): dt=l.split()[1]
        m=re.match(r'^\+\["([^"]+)"\]',l)
        if m and m.group(1) not in r: r[m.group(1)]=D(dt)
    return r
REG={}
for p in SET:
    base=f"general/{p[0]}/{p}/"
    vt=tomllib.load(open(base+"Versions.toml","rb")); dates=regdates(p)
    def load(n):
        try: return tomllib.load(open(base+n,"rb"))
        except FileNotFoundError: return {}
    deps={**{}}; DT=[load("Deps.toml"),load("WeakDeps.toml")]; CT=[load("Compat.toml"),load("WeakCompat.toml")]
    vers={}
    for v,x in vt.items():
        if x.get('yanked'): continue
        vv=V(v); dd=set(); cc={}
        for T in DT:
            for k,tab in T.items():
                if inr(k,vv): dd|=set(tab)&set(SET)
        for T in CT:
            for k,tab in T.items():
                if inr(k,vv):
                    for q,spec in tab.items():
                        if q in SET: cc[q]=spec
        vers[v]=dict(date=dates.get(v,OLD),deps=dd,compat=cc)
    REG[p]=vers
# transitive dependency closure (any version)
anydeps={p:set().union(*[x['deps'] for x in REG[p].values()]) if REG[p] else set() for p in SET}
def reaches(p,u,seen=()):
    if u in anydeps[p]: return True
    return any(reaches(q,u,seen+(p,)) for q in anydeps[p] if q not in seen)
def depth(p,u,memo={}):
    if (p,u) in memo: return memo[(p,u)]
    ds=[1] if u in anydeps[p] else []
    ds+=[1+depth(q,u) for q in anydeps[p] if q!=u and reaches(q,u)]
    memo[(p,u)]=max(ds) if ds else 0; return memo[(p,u)]
# topo order
order=[]; 
def visit(p,st=set()):
    if p in order: return
    for q in anydeps[p]: 
        if q not in st: visit(q,st|{p})
    order.append(p)
for p in SET: visit(p)
ADM={}
for line in open("specs_out.tsv"):
    pkg,spec,ok=line.rstrip("\n").split("\t"); ADM[(pkg,spec)]=set(ok.split(",")) if ok else set()
H=json.load(open("compat_history_all.json"))
brk={(r['pkg'],r['version']):r['breaking']=='1' for r in csv.DictReader(open("versions.csv"))}
WSTART=D("2025-09-28T00:00:00+00:00")
rows=[]
for u in UP:
    for uv,t0 in sorted(REG[u].items(),key=lambda x:x[1]['date']):
        t0=t0['date']
        if t0<WSTART: continue
        ready={u:{uv:t0}}   # pkg -> {version: ready_date}
        bott={}
        for p in order:
            if p==u or not reaches(p,u): continue
            rp={}
            for pv,info in REG[p].items():
                R=[q for q in info['deps'] if q==u or (q in ready and q!=p)]
                if not R: rp[pv]=max(info['date'],t0); continue  # imposes no constraint on U
                dt=max(info['date'],t0); ok=True
                for q in R:
                    spec=info['compat'].get(q)
                    cands=[d for qv,d in ready.get(q,{}).items() if spec is None or inr(spec,V(qv))]
                    if not cands: ok=False; break
                    dt=max(dt,min(cands))
                if ok: rp[pv]=dt
            ready[p]=rp
        for s in SINKS:
            if not reaches(s,u): continue
            direct_now = u in H[s][-1]['deps'] if H.get(s) else False
            regs=[d for sv,d in ready.get(s,{}).items() if (u in REG[s][sv]['deps']) or (not direct_now and [q for q in REG[s][sv]['deps'] if q in ready])]
            reg=min(regs,default=None)
            # main-branch variant: snapshot compat with Julia semver semantics, deps must be ready (registered)
            best=None; bneck=''
            SS=H.get(s,[]); prev=[i for i,x in enumerate(SS) if D(x['date'])<t0]; SS=SS[prev[-1]:] if prev else SS
            for snap in SS:
                R=[q for q in snap['deps'] if q==u or q in ready]
                if not R: continue
                base=max(D(snap['date']),t0); sd=base; ok=True; bq='(own compat)' if D(snap['date'])>t0 else '(pre-admitted)'
                for q in R:
                    spec=snap['compat'].get(q)
                    if spec is not None and re.search(r'[<>*]',spec): ok=False; break
                    if q==u:
                        if spec is not None and uv not in ADM.get((q,spec),set()): ok=False; break
                        continue
                    cands=[d for qv,d in ready[q].items() if spec is None or qv in ADM.get((q,spec),set())]
                    if not cands: ok=False; break
                    if min(cands)>sd: sd=min(cands); bq=q
                if ok and (best is None or sd<best): best=sd; bneck=bq
            rows.append(dict(upstream=u,version=uv,breaking=int(brk.get((u,uv),False)),released=t0.isoformat()[:19],sink=s,chain_depth=depth(s,u),
                main_ready_lag_days=round((best-t0).total_seconds()/86400,2) if best else '',
                registered_ready_lag_days=round((reg-t0).total_seconds()/86400,2) if reg else '',main_bottleneck=bneck))
w=csv.DictWriter(open("e2e_lag.csv","w"),fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
def pct(L,p):
    L=sorted(L); k=(len(L)-1)*p; f=int(k); c=min(f+1,len(L)-1); return round(L[f]+(L[c]-L[f])*(k-f),2)
for key in ("main_ready_lag_days","registered_ready_lag_days"):
    for b in (1,0):
        R=[r for r in rows if r['breaking']==b]; L=[r[key] for r in R if r[key]!='']
        print(key,"breaking" if b else "nonbreaking","n",len(R),"ready",len(L),"med",pct(L,.5),"p90",pct(L,.9),"max",max(L),"never",len(R)-len(L))
print()
for r in rows:
    if r['breaking']: print(r['upstream'],r['version'],r['sink'],"depth",r['chain_depth'],"main",r['main_ready_lag_days'],"reg",r['registered_ready_lag_days'],r['main_bottleneck'])
print({(u,s):depth(s,u) for u in UP for s in SINKS if reaches(s,u)})
