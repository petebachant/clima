import subprocess,tomllib,json
SET="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
G="repos/ClimaCoupler"; FILES=["Project.toml","experiments/ClimaEarth/Project.toml"]
log=subprocess.run(["git","-C",G,"log","--first-parent","origin/HEAD","--since=2024-09-01","--reverse","--format=%H %cI","--"]+FILES,capture_output=True,text=True).stdout.split("\n")
snaps=[]
for line in filter(None,log):
    h,dt=line.split(); deps=set(); comp={}
    for f in FILES:
        r=subprocess.run(["git","-C",G,"show",f"{h}:{f}"],capture_output=True,text=True)
        if r.returncode: continue
        t=tomllib.loads(r.stdout)
        d=(set(t.get('deps',{}))|set(t.get('weakdeps',{})))&set(SET)
        for k,v in t.get('compat',{}).items():
            if k in d: 
                v=",".join(v) if isinstance(v,list) else v
                # intersection semantics: root first; ClimaEarth only fills missing (it is the env actually used for runs)
                comp.setdefault(k,v)
        deps|=d
    snaps.append(dict(date=dt,sha=h,deps=sorted(deps),compat=comp))
H=json.load(open("compat_history_all.json")); H["ClimaCoupler"]=snaps
json.dump(H,open("compat_history_all.json","w"),indent=0); print(len(snaps))
