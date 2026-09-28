import json,csv,subprocess,re,statistics,collections,tomllib
from datetime import datetime,timezone
UP="ClimaComms ClimaCore Thermodynamics CloudMicrophysics SurfaceFluxes ClimaUtilities ClimaParams ClimaTimeSteppers ClimaDiagnostics RRTMGP RootSolvers Insolation".split()
H=json.load(open("compat_history_all.json"))
ADM={}
for line in open("specs_out.tsv"):
    pkg,spec,ok=line.rstrip("\n").split("\t"); ADM[(pkg,spec)]=set(ok.split(",")) if ok else set()
def V(s): return tuple(int(x) for x in s.split('+')[0].split('-')[0].split('.'))
def D(s): return datetime.fromisoformat(s).astimezone(timezone.utc)
# registry ISO dates
def regdates(pkg):
    out=subprocess.run(["git","-C","general","log","--format=COMMIT %cI","-p","--",f"{pkg[0]}/{pkg}/Versions.toml"],capture_output=True,text=True).stdout
    dt=None; r={}
    for l in out.splitlines():
        if l.startswith("COMMIT "): dt=l.split()[1]
        m=re.match(r'^\+\["([^"]+)"\]',l)
        if m and m.group(1) not in r: r[m.group(1)]=dt
    return r
brk={(r['pkg'],r['version']):r['breaking']=='1' for r in csv.DictReader(open("versions.csv"))}
WSTART=D("2025-09-28T00:00:00+00:00"); NOW=D("2026-09-28T23:59:59+00:00")
rows=[]
REG={}
for u in UP:
    rd=regdates(u); REG[u]=rd
    rels=sorted([(v,D(t)) for v,t in rd.items() if D(t)>=WSTART and (u,v) in brk],key=lambda x:x[1])
    for i,(v,t) in enumerate(rels):
        nxt=rels[i+1] if i+1<len(rels) else None
        for d,S in H.items():
            if d==u: continue
            if not any(u in s['deps'] for s in S if D(s['date'])<=NOW and D(s['date'])>=WSTART) : continue
            pre=[s for s in S if D(s['date'])<t]
            dep_at_rel = pre and u in pre[-1]['deps']
            if not dep_at_rel: continue
            def adm(s):
                if u not in s['deps']: return False
                if u not in s['compat']: return True   # no compat entry = unbounded
                sp=s['compat'][u]
                if re.search(r'[<>*]',sp): return False   # ignore unbounded inequality specs as 'adoption'
                return v in ADM.get((u,sp),set())
            pre_ok = bool(pre) and adm(pre[-1])
            first=None
            if not pre_ok:
                for s in S:
                    if D(s['date'])>=t and adm(s): first=s; break
            lag = 0.0 if pre_ok else ((D(first['date'])-t).total_seconds()/86400 if first else None)
            sup = nxt is not None and not pre_ok and (first is None or D(first['date'])>=nxt[1])
            rows.append(dict(upstream=u,version=v,breaking=int(brk[(u,v)]),released=t.isoformat()[:19],dependent=d,pre_admitted=int(pre_ok),
                first_admit=(first['date'][:19] if first else ('' if not pre_ok else 'pre')),sha=(first['sha'][:10] if first else ''),
                lag_days=round(lag,2) if lag is not None else '',never_admitted=int(lag is None),
                next_release=nxt[0] if nxt else '',superseded_before_adoption=int(sup)))
w=csv.DictWriter(open("propagation_lag.csv","w"),fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
json.dump({u:REG[u] for u in REG},open("registry_dates_iso.json","w"))
def pct(L,p):
    L=sorted(L);
    if not L: return None
    k=(len(L)-1)*p; f=int(k); c=min(f+1,len(L)-1); return round(L[f]+(L[c]-L[f])*(k-f),2)
def stats(R):
    L=[r['lag_days'] for r in R if r['lag_days']!='']
    Lp=[x for r,x in ((r,r['lag_days']) for r in R) if x!='' and not r['pre_admitted']]
    return dict(n=len(R),pre=sum(r['pre_admitted'] for r in R),med=pct(L,.5),p90=pct(L,.9),max=max(L) if L else None,
        n_post=len(Lp),med_post=pct(Lp,.5),p90_post=pct(Lp,.9),never=sum(r['never_admitted'] for r in R),superseded=sum(r['superseded_before_adoption'] for r in R))
print("OVERALL",stats(rows))
for b in (1,0): print("breaking" if b else "nonbreaking",stats([r for r in rows if r['breaking']==b]))
print("\nPer edge (breaking):")
E=collections.defaultdict(list)
for r in rows: E[(r['upstream'],r['dependent'],r['breaking'])].append(r)
out=[]
for (u,d,b),R in sorted(E.items()):
    s=stats(R); s.update(upstream=u,dependent=d,breaking=b); out.append(s)
w=csv.DictWriter(open("propagation_lag_by_edge.csv","w"),fieldnames=["upstream","dependent","breaking"]+[k for k in out[0] if k not in("upstream","dependent","breaking")]); w.writeheader(); w.writerows(out)
for s in out:
    if s['breaking']: print(s)
print("\nnonbreaking edges with any not-pre-admitted:")
for s in out:
    if not s['breaking'] and s['pre']<s['n']: print(s)
