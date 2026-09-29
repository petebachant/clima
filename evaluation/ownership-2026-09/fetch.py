import json, subprocess, sys, collections
Q = '''query($repo:String!,$cursor:String){repository(owner:"CliMA",name:$repo){pullRequests(states:MERGED,first:100,after:$cursor,orderBy:{field:UPDATED_AT,direction:DESC}){pageInfo{hasNextPage endCursor}nodes{number mergedAt author{login} mergedBy{login} reviews(first:30,states:[APPROVED,CHANGES_REQUESTED,COMMENTED]){nodes{author{login} state}}}}}}'''
BOTS = {"github-actions","dependabot","JuliaTagBot","JuliaRegistrator","github-actions[bot]","copilot-pull-request-reviewer","Copilot","CompatHelper"}
out = {}
REPO = lambda r: r if r == "DeveloperGuides" else r + ".jl"
for repo in sys.argv[1:]:
    prs, cursor = [], None
    while True:
        args = ["gh","api","graphql","-f",f"query={Q}","-f",f"repo={REPO(repo)}"] + (["-f",f"cursor={cursor}"] if cursor else [])
        d = json.loads(subprocess.check_output(args))["data"]["repository"]["pullRequests"]
        new = [p for p in d["nodes"] if p["mergedAt"] >= "2025-09-28"]
        prs += new
        if not d["pageInfo"]["hasNextPage"] or len(new) == 0: break
        cursor = d["pageInfo"]["endCursor"]
    rev, auth, merg = collections.Counter(), collections.Counter(), collections.Counter()
    for p in prs:
        a = (p["author"] or {}).get("login")
        if a in BOTS or (a or "").endswith("[bot]"): continue
        auth[a] += 1
        if p["mergedBy"]: merg[p["mergedBy"]["login"]] += 1
        for r in {(x["author"] or {}).get("login") for x in p["reviews"]["nodes"]} - {a, None}:
            if r not in BOTS and not r.endswith("[bot]"): rev[r] += 1
    out[repo] = {"n": sum(auth.values()), "reviewers": rev.most_common(6), "authors": auth.most_common(6)}
    print(repo, out[repo]["n"], "rev:", rev.most_common(5), "auth:", auth.most_common(4), flush=True)
json.dump(out, open("owners.json","w"), indent=1)
