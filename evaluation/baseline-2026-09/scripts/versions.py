import subprocess, re, csv, os, json
PKGS="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
G="general"
def V(s): return tuple(int(x) for x in re.match(r'(\d+)\.(\d+)\.(\d+)',s).groups())
rows=[]
for p in PKGS:
    d=f"{p[0]}/{p}/Versions.toml"
    allv=sorted({m for m in re.findall(r'^\["([^"]+)"\]',open(f"{G}/{d}").read(),re.M)},key=V)
    out=subprocess.run(["git","-C",G,"log","--since=2025-09-28","--format=COMMIT %cs","-p","--",d],capture_output=True,text=True).stdout
    date=None; dates={}
    for line in out.splitlines():
        if line.startswith("COMMIT "): date=line.split()[1]
        m=re.match(r'^\+\["([^"]+)"\]',line)
        if m and m.group(1) not in dates: dates[m.group(1)]=date
    for v,dt in dates.items():
        if dt<"2025-09-28": continue
        if v not in allv: continue  # yanked-and-removed? keep simple
        prior=[x for x in allv if V(x)<V(v)]
        # breaking = new major, or new minor on 0.x relative to highest prior
        prev=prior[-1] if prior else None
        a=V(v); b=V(prev) if prev else (0,0,0)
        brk = prev is None or (a[0]>b[0]) or (a[0]==0 and b[0]==0 and a[1]>b[1])
        # "backport": lower than max prior
        rows.append(dict(pkg=p,version=v,date=dt,prev=prev,breaking=int(brk)))
rows.sort(key=lambda r:(r['pkg'],V(r['version'])))
with open("versions.csv","w") as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
from collections import defaultdict
s=defaultdict(lambda:[0,0,[]])
for r in rows:
    s[r['pkg']][0]+=1; s[r['pkg']][1]+=r['breaking']
    if r['breaking']: s[r['pkg']][2].append(r['version'])
for p in PKGS: print(p, s[p][0], s[p][1], ",".join(s[p][2]))
print("TOTAL",len(rows),sum(r['breaking'] for r in rows))
