import json,re,csv,glob,os
PKGS="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
ALIAS={"CM":"CloudMicrophysics","TD":"Thermodynamics","SF":"SurfaceFluxes","CTS":"ClimaTimeSteppers","CP":"ClimaParams","CC":"ClimaCore"}
REL=re.compile(r'\b(release|patch release|tag|bump version|version bump|bump to v?\d|^v?\d+\.\d+\.\d+$|version \d|new version|\(\d+\.\d+\.\d+\))',re.I)
COMPAT=re.compile(r'(compathelper|\bcompat\b|\bbump\b.*\b(to|from)\b|update (deps|dependencies)|up deps|\bdeps?\b.*(update|bump)|(update|upgrade|bump|move|migrate|adapt)\w* (to|for) \S+ v?\d)',re.I)
UP=re.compile(r'\b('+'|'.join(PKGS+list(ALIAS))+r')(\.jl)?\b')
META=re.compile(r'(^|/)(Project\.toml|Manifest[-\w.]*\.toml|NEWS\.md|CHANGELOG\.md)$')
rows=[]
for p in PKGS:
    for pr in json.load(open(f"prs/{p}.json")):
        t=pr['title']; files=[f['path'] for f in pr.get('files') or []]
        meta_only = bool(files) and all(META.search(f) for f in files)
        rel = bool(REL.search(t))
        compat = bool(COMPAT.search(t)) or pr['author']['login'] in ('github-actions','app/github-actions') and 'compat' in t.lower()
        ups = sorted({ALIAS.get(m[0],m[0]) for m in UP.findall(t)} - {p})
        upgrade = bool(ups) and bool(re.search(r'(update|upgrade|bump|compat|adapt|migrat|support|move to|v\d|\d+\.\d+)',t,re.I))
        gha = bool(re.match(r'bump [\w.-]+/[\w.-]+ from',t,re.I)) or 'dependabot' in pr['author']['login']
        cat = 'gha-bump' if gha else 'release' if rel and not upgrade else ('compat/upgrade' if (compat or upgrade) else ('meta-only-other' if meta_only else 'other'))
        rows.append(dict(repo=p,number=pr['number'],mergedAt=pr['mergedAt'][:10],author=pr['author']['login'],title=t,
            n_files=len(files),meta_only=int(meta_only),release=int(rel),compat=int(compat),upstream_upgrade=int(upgrade),upstreams=";".join(ups),category=cat,url=pr['url']))
with open("prs_classified.csv","w") as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(f"{'repo':20} {'all':>4} {'rel':>4} {'cmp':>4} {'metaOnly':>8} {'churn':>5} {'frac':>5}")
T=[0]*5; summ=[]
for p in PKGS:
    R=[r for r in rows if r['repo']==p]
    a=len(R); rel=sum(r['category']=='release' for r in R); cmp_=sum(r['category']=='compat/upgrade' for r in R)
    mo=sum(r['meta_only'] and r['category']!='gha-bump' for r in R); churn=sum(r['category']!='gha-bump' and (r['category'] in('release','compat/upgrade') or r['meta_only']) for r in R); gh_=sum(r['category']=='gha-bump' for r in R); ins=sum(r['category']=='compat/upgrade' and bool(r['upstreams']) for r in R)
    for i,x in enumerate([a,rel,cmp_,mo,churn]): T[i]+=x
    print(f"{p:20} {a:4} {rel:4} {cmp_:4} {mo:8} {churn:5} {churn/a if a else 0:5.2f} gha={gh_} inset_upgrade={ins}"); summ.append(dict(repo=p,merged=a,release=rel,compat_upgrade=cmp_,compat_upgrade_inset=ins,meta_only=mo,churn_union=churn,churn_frac=round(churn/a,3) if a else 0,gha_bumps=gh_))
print(f"{'TOTAL':20} {T[0]:4} {T[1]:4} {T[2]:4} {T[3]:8} {T[4]:5} {T[4]/T[0]:5.2f}")

import csv
w=csv.DictWriter(open('churn_summary.csv','w'),fieldnames=list(summ[0])); w.writeheader(); w.writerows(summ)
