import json,re,csv,collections
PKGS="ClimaComms ClimaParams RootSolvers ClimaInterpolations Thermodynamics SurfaceFluxes CloudMicrophysics Insolation RRTMGP ClimaCore ClimaTimeSteppers ClimaUtilities ClimaDiagnostics ClimaAnalysis ClimaAtmos ClimaLand ClimaCoupler ClimaCalibrate".split()
REF=re.compile(r'(?:(?:github\.com/)?CliMA/)?\b('+'|'.join(PKGS)+r')(?:\.jl)?(?:#|/pull/|/issues/|\s+(?:PR|pull request|issue)\s*#?|\s+#)(\d+)',re.I)
KW=re.compile(r'\b(needs?|depends? on|dependent on|requires?|required by|blocked (by|on)|after|companion|counterpart|together with|in tandem|paired|goes with|accompan\w+|merged (first|before)|downstream|upstream|to be merged|wait(s|ing)? (for|on))\b',re.I)
NORM={p.lower():p for p in PKGS}
rows=[]; tot=collections.Counter(); hit=collections.Counter(); hitkw=collections.Counter(); pairs=collections.Counter()
for p in PKGS:
    for pr in json.load(open(f"prs/{p}.json")):
        if re.search(r'github-actions|dependabot',pr['author']['login']): continue
        tot[p]+=1
        b=pr['body'] or ''
        b=re.sub(r'<details>.*?</details>','',b,flags=re.S)
        refs=sorted({(NORM[m[0].lower()],m[1]) for m in REF.findall(b) if NORM[m[0].lower()]!=p})
        if not refs: continue
        hit[p]+=1
        # keyword within ~120 chars of a ref
        kw=False
        for m in REF.finditer(b):
            if NORM[m.group(1).lower()]==p: continue
            ctx=b[max(0,m.start()-150):m.end()+50]
            if KW.search(ctx): kw=True
        if kw: hitkw[p]+=1
        for r,_ in refs: pairs[(p,r)]+=1
        rows.append(dict(repo=p,number=pr['number'],merged=pr['mergedAt'][:10],dep_keyword=int(kw),refs=";".join(f"{r}#{n}" for r,n in refs),title=pr['title'],url=pr['url']))
w=csv.DictWriter(open("cross_repo_refs.csv","w"),fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
summ=[]
for p in PKGS:
    print(f"{p:20} human_merged={tot[p]:4} xref={hit[p]:3} xref+kw={hitkw[p]:3} frac={hit[p]/tot[p]:.2f}")
    summ.append(dict(repo=p,human_merged=tot[p],xref=hit[p],xref_dep_kw=hitkw[p]))
print("TOTAL",sum(tot.values()),sum(hit.values()),sum(hitkw.values()))
csv.DictWriter(open("cross_repo_summary.csv","w"),fieldnames=list(summ[0])).writeheader()
w=csv.DictWriter(open("cross_repo_summary.csv","a"),fieldnames=list(summ[0])); w.writerows(summ)
print(pairs.most_common(20))
