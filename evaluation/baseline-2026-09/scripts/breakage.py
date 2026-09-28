import json,re,csv
PKGS="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCalibrate".split()
UP=re.compile(r'\b('+'|'.join(PKGS)+r')(\.jl)?\b')
BRK=re.compile(r"\b(break|breaks|broke|broken|breakage|breaking)\b|fix(es|ed)? compat|\bdownstream\b|new release of|incompatib|regression|\bfails? (with|on|after)\b|error (after|with) (the )?(new|latest|updat)",re.I)
TBRK=re.compile(r"\b(break|breaks|broke|broken|breakage)\b|fix(es|ed)? (for|after|compat)|incompatib|regression|\bfail|\berror|deprecat",re.I)
rows=[]
for p in ["ClimaAtmos","ClimaLand","ClimaCoupler"]:
    for kind,f in [("issue",f"issues/{p}.json"),("pr",f"issues/{p}_allprs.json")]:
        for x in json.load(open(f)):
            if re.search(r'github-actions|dependabot',x['author']['login']): continue
            t=x['title']; b=x['body'] or ''
            # strip HTML release-note blocks (quoted from bots/users)
            b2=re.sub(r'<details>.*?</details>','',b,flags=re.S)
            ups=sorted({m[0] for m in UP.findall(t+" "+b2)}-{p})
            if not ups: continue
            broad=bool(BRK.search(t+" "+b2)); strict=bool(TBRK.search(t)) and bool(UP.search(t))
            if broad or strict:
                rows.append(dict(repo=p,kind=kind,number=x['number'],created=x['createdAt'][:10],state=x['state'],broad=int(broad),strict_title=int(strict),upstreams=";".join(ups),title=t,url=x['url']))
w=csv.DictWriter(open("breakage_candidates.csv","w"),fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
import collections
for p in ["ClimaAtmos","ClimaLand","ClimaCoupler"]:
    R=[r for r in rows if r['repo']==p]
    print(p,"broad",sum(r['broad'] for r in R),"(issues",sum(r['broad'] and r['kind']=='issue' for r in R),") strict",sum(r['strict_title'] for r in R))
for r in rows:
    if r['strict_title']: print(r['repo'][:9],r['kind'],r['created'],r['title'][:90],r['url'])
