import subprocess,tomllib,json,re
DEPS="ClimaAtmos ClimaLand ClimaCoupler ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics RRTMGP SurfaceFluxes CloudMicrophysics Thermodynamics".split()
SET="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
H={}
for d in DEPS:
    G=f"repos/{d}"
    log=subprocess.run(["git","-C",G,"log","--first-parent","origin/HEAD","--since=2024-09-01","--reverse","--format=%H %cI","--","Project.toml"],capture_output=True,text=True).stdout.split("\n")
    # also the state just before the since date
    base=subprocess.run(["git","-C",G,"log","--first-parent","origin/HEAD","--until=2024-09-01","-1","--format=%H %cI","--","Project.toml"],capture_output=True,text=True).stdout.strip()
    lines=([base] if base else [])+[l for l in log if l]
    snaps=[]
    for line in lines:
        h,dt=line.split()
        txt=subprocess.run(["git","-C",G,"show",f"{h}:Project.toml"],capture_output=True,text=True).stdout
        try: t=tomllib.loads(txt)
        except Exception: continue
        deps=sorted((set(t.get('deps',{}))|set(t.get('weakdeps',{})))&set(SET))
        comp={k:(",".join(v) if isinstance(v,list) else v) for k,v in t.get('compat',{}).items() if k in SET}
        snaps.append(dict(date=dt,sha=h,deps=deps,compat=comp))
    H[d]=snaps; print(d,len(snaps),snaps[0]['date'][:10])
json.dump(H,open("compat_history_all.json","w"),indent=0)
