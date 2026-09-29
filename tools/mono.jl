# Monorepo helper. Stdlib only, so it runs before anything is instantiated.
#
#   julia tools/mono.jl graph                     # packages in dependency order
#   julia tools/mono.jl affected [BASE|ALL] [--docs]  # changed pkgs + everything downstream (JSON)
#   julia tools/mono.jl compat [--strict]         # in-repo compat drift report
#   julia tools/mono.jl test PKG [--registered]   # test PKG against in-repo HEAD of its deps
#   julia tools/mono.jl bump PKG LEVEL [--release-dependents]
#                                                 # LEVEL = major|minor|patch; widens dependents' compat
#   julia tools/mono.jl releases BASE             # pkgs whose version changed since BASE (JSON)
#   julia tools/mono.jl workspace                 # regenerate root Project.toml [workspace]
#   julia tools/mono.jl buildkite [BASE]          # emit GPU/MPI pipeline for affected pkgs
#   julia tools/mono.jl examples [BASE|ALL] [--pr]  # affected cross-package examples (JSON)
#   julia tools/mono.jl examples --list           # markdown table of examples
#   julia tools/mono.jl sources DIR               # point DIR/Project.toml's in-repo deps at their paths
#   julia tools/mono.jl codeowners                # regenerate CODEOWNERS, triage map, issue form
#
# "In-repo" means listed in packages.toml with a Project.toml at its path.

using TOML, Pkg

const ROOT = normpath(joinpath(@__DIR__, ".."))

struct Package
    name::String
    path::String            # relative to ROOT
    version::VersionNumber
    deps::Vector{String}    # in-repo hard deps
    weakdeps::Vector{String}
    testdeps::Vector{String}
    compat::Dict{String, String}
    testcompat::Dict{String, String}  # from test/Project.toml, if any
end

function testdeps_of(dir, project)
    names = String[]
    tp = joinpath(dir, "test", "Project.toml")
    if isfile(tp)
        append!(names, keys(get(TOML.parsefile(tp), "deps", Dict())))
    end
    for t in get(get(project, "targets", Dict()), "test", String[])
        push!(names, t)
    end
    return names
end

function testcompat_of(dir)
    tp = joinpath(dir, "test", "Project.toml")
    isfile(tp) ? get(TOML.parsefile(tp), "compat", Dict{String, String}()) :
    Dict{String, String}()
end

function load_packages()
    manifest = TOML.parsefile(joinpath(ROOT, "packages.toml"))
    raw = Dict{String, Tuple{String, Dict}}()
    for (name, entry) in manifest
        haskey(entry, "path") && get(entry, "julia", true) || continue
        proj = joinpath(ROOT, entry["path"], "Project.toml")
        isfile(proj) || continue
        raw[name] = (entry["path"], TOML.parsefile(proj))
    end
    inrepo(xs) = sort!(filter(in(keys(raw)), collect(xs)))
    pkgs = Dict{String, Package}()
    for (name, (path, p)) in raw
        pkgs[name] = Package(
            name, path, VersionNumber(p["version"]),
            inrepo(keys(get(p, "deps", Dict()))),
            inrepo(keys(get(p, "weakdeps", Dict()))),
            inrepo(testdeps_of(joinpath(ROOT, path), p)),
            get(p, "compat", Dict{String, String}()),
            testcompat_of(joinpath(ROOT, path)),
        )
    end
    return pkgs
end

# Edges that matter when deciding what to re-test: anything that can load the
# upstream package, including extensions and test-only use.
test_edges(p::Package) = unique!(vcat(p.deps, p.weakdeps, p.testdeps))

function toposort(pkgs)
    order, seen = String[], Set{String}()
    visit(n) = n in seen || (push!(seen, n); foreach(visit, pkgs[n].deps); push!(order, n))
    foreach(visit, sort!(collect(keys(pkgs))))
    return order
end

function dependents(pkgs)
    rev = Dict(n => String[] for n in keys(pkgs))
    for p in values(pkgs), d in test_edges(p)
        d == p.name || push!(rev[d], p.name)
    end
    return rev
end

function downstream_closure(pkgs, roots)
    rev, out, stack = dependents(pkgs), Set{String}(roots), collect(roots)
    while !isempty(stack)
        for d in rev[pop!(stack)]
            d in out || (push!(out, d); push!(stack, d))
        end
    end
    return out
end

# Transitive in-repo deps needed to test `name` (hard deps, plus test deps).
function upstream_closure(pkgs, name)
    out, stack = Set{String}(), copy(test_edges(pkgs[name]))
    while !isempty(stack)
        n = pop!(stack)
        n in out || n == name || (push!(out, n); append!(stack, pkgs[n].deps))
    end
    return out
end

git(args...) = readchomp(Cmd(`git -C $ROOT $args`))

# A usable diff base? GitHub sends 40 zeros as `github.event.before` on a
# branch's first push, and a force-push's old SHA may no longer exist.
valid_base(base) =
    !occursin(r"^0+$", base) &&
    success(
        pipeline(
            `git -C $ROOT rev-parse --verify --quiet $(base * "^{commit}")`;
            stdout = devnull,
        ),
    )

# Files changed since BASE, or `nothing` when BASE can't be diffed against.
function changed_files(base)
    valid_base(base) || return nothing
    return split(git("diff", "--name-only", "$base...HEAD"), '\n'; keepempty = false)
end

function changed_packages(pkgs, base)
    base == "ALL" && return Set(keys(pkgs))
    files = changed_files(base)
    if files === nothing
        @warn "Can't diff against $base; treating every package as affected"
        return Set(keys(pkgs))
    end
    hit = Set{String}()
    for f in files, p in values(pkgs)
        startswith(f, p.path * "/") && push!(hit, p.name)
    end
    # Shared infrastructure touches everyone.
    any(f -> startswith(f, "tools/") || f in ("packages.toml", "Project.toml"), files) &&
        union!(hit, keys(pkgs))
    return hit
end

json_list(xs) = "[" * join(("\"$x\"" for x in xs), ",") * "]"
json_matrix(pkgs, names) =
    "[" * join(("{\"package\":\"$n\",\"path\":\"$(pkgs[n].path)\"}" for n in names), ",") *
    "]"

# ---------------------------------------------------------------------------

function cmd_graph(pkgs)
    rev = dependents(pkgs)
    for n in toposort(pkgs)
        p = pkgs[n]
        println(rpad("$n v$(p.version)", 32), "deps: ", join(p.deps, ", "))
        isempty(rev[n]) || println(" "^32, "used by: ", join(sort(rev[n]), ", "))
    end
end

function cmd_affected(pkgs, base = "origin/main"; docs = false)
    order = toposort(pkgs)
    affected = downstream_closure(pkgs, changed_packages(pkgs, base))
    docs && filter!(n -> isfile(joinpath(ROOT, pkgs[n].path, "docs", "make.jl")), affected)
    println(json_matrix(pkgs, filter(in(affected), order)))
end

function compat_drift(pkgs)
    drift = Tuple{String, String, String, VersionNumber}[]
    check(where, d, spec) =
        spec === nothing || pkgs[d].version in Pkg.Versions.semver_spec(spec) ||
        push!(drift, (where, d, spec, pkgs[d].version))
    for p in values(pkgs)
        for d in unique!(vcat(p.deps, p.weakdeps))
            spec = get(p.compat, d, nothing)
            spec === nothing ? push!(drift, (p.name, d, "<missing>", pkgs[d].version)) :
            check(p.name, d, spec)
        end
        # Test envs: a stale bound silently tests against an old release.
        for (d, spec) in p.testcompat
            haskey(pkgs, d) && check("$(p.name)/test", d, spec)
        end
    end
    return sort!(drift)
end

function cmd_compat(pkgs, strict = false)
    drift = compat_drift(pkgs)
    if isempty(drift)
        println("All in-repo compat bounds admit the in-repo versions.")
    else
        println("Compat drift (dependent's [compat] excludes the in-repo version):")
        for (p, d, spec, v) in drift
            println("  $p -> $d: compat \"$spec\" excludes in-repo v$v")
        end
    end
    strict && !isempty(drift) && exit(1)
end

function cmd_test(pkgs, name, registered = false)
    p = pkgs[name]
    dir = joinpath(ROOT, p.path)
    ups = registered ? String[] : sort!(collect(upstream_closure(pkgs, name)))
    specs = [Pkg.PackageSpec(path = joinpath(ROOT, pkgs[u].path)) for u in ups]
    println(
        "Testing $name against ",
        registered ? "registered deps" :
        "in-repo HEAD of: " * (isempty(ups) ? "(none)" : join(ups, ", ")),
    )
    if isfile(joinpath(dir, "test", "Project.toml"))
        # Mirrors the existing CliMA convention: dev the package into its test env.
        env = mktempdir()
        cp(joinpath(dir, "test", "Project.toml"), joinpath(env, "Project.toml"))
        Pkg.activate(env)
        Pkg.develop(vcat(Pkg.PackageSpec(path = dir), specs))
        Pkg.instantiate()
        cd(joinpath(dir, "test")) do
            run(`$(Base.julia_cmd()) --color=yes --project=$env runtests.jl`)
        end
    else
        env = mktempdir()
        cp(dir, env; force = true)  # keep the tracked Project.toml clean
        Pkg.activate(env)
        isempty(specs) || Pkg.develop(specs)
        Pkg.test()
    end
end

function bump(v::VersionNumber, level)
    level == "patch" && return VersionNumber(v.major, v.minor, v.patch + 1)
    level == "minor" && return VersionNumber(v.major, v.minor + 1, 0)
    level == "major" && return VersionNumber(v.major + 1, 0, 0)
    error("LEVEL must be major, minor, or patch")
end

# Julia semver: 0.x minor and x.0 major bumps are breaking.
isbreaking(old, new) =
    old.major == 0 ? new.minor != old.minor || new.major != 0 :
    new.major != old.major

compat_entry(v) = v.major == 0 ? "$(v.major).$(v.minor)" : "$(v.major)"

# Line-based edits so Project.toml formatting and comments survive.
function edit_project(f, path)
    lines = readlines(path)
    section = ""
    for (i, l) in enumerate(lines)
        m = match(r"^\s*\[(.+)\]\s*$", l)
        m === nothing ? (lines[i] = f(section, l)) : (section = m[1])
    end
    write(path, join(lines, '\n') * '\n')
end

function widen_compat!(path, dep, new)
    isfile(path) || return nothing
    spec = get(get(TOML.parsefile(path), "compat", Dict()), dep, nothing)
    (spec === nothing || new in Pkg.Versions.semver_spec(spec)) && return nothing
    widened = "$spec, $(compat_entry(new))"
    edit_project(path) do section, l
        section == "compat" && occursin(Regex("^\\s*$dep\\s*="), l) ?
        "$dep = \"$widened\"" : l
    end
    return spec => widened
end

function set_version!(p::Package, new)
    edit_project(joinpath(ROOT, p.path, "Project.toml")) do section, l
        section == "" && startswith(l, "version") ? "version = \"$new\"" : l
    end
    println("$(p.name): $(p.version) -> $new")
end

function cmd_bump(pkgs, name, level, release_dependents = false)
    p = pkgs[name]
    new = bump(p.version, level)
    set_version!(p, new)
    isbreaking(p.version, new) || return
    # Breaking: widen every in-repo dependent's compat (package and test env)
    # in the same change, so the whole graph keeps resolving.
    touched = String[]
    for q in values(pkgs), f in ("Project.toml", joinpath("test", "Project.toml"))
        r = widen_compat!(joinpath(ROOT, q.path, f), name, new)
        r === nothing && continue
        println("  $(q.name)/$f: compat $name \"$(r.first)\" -> \"$(r.second)\"")
        f == "Project.toml" && push!(touched, q.name)
    end
    isempty(touched) && return
    if release_dependents
        # Users only see widened compat once the dependent is released.
        foreach(n -> set_version!(pkgs[n], bump(pkgs[n].version, "patch")), sort!(touched))
    else
        println(
            "Dependents with widened compat need a release before users can combine them",
            " with $name $new; pass --release-dependents to patch-bump them.")
    end
end

# Packages whose version changed since BASE, in dependency order. `waits_for`
# lists in-repo deps released in the same batch, which must reach General first.
function cmd_releases(pkgs, base)
    # Never guess here: an unknown base would make every package look bumped
    # and register all of them.
    valid_base(base) || error("releases: can't resolve base $base; pass an explicit ref")
    out = String[]
    for n in toposort(pkgs)
        p = pkgs[n]
        old = try
            TOML.parse(git("show", "$base:$(p.path)/Project.toml"))["version"]
        catch
            nothing  # new package
        end
        old == string(p.version) || push!(out, n)
    end
    entries = map(out) do n
        waits = join(("\"$d@$(pkgs[d].version)\"" for d in pkgs[n].deps if d in out), ",")
        "{\"package\":\"$n\",\"path\":\"$(pkgs[n].path)\",\"version\":\"$(pkgs[n].version)\",\"waits_for\":[$waits]}"
    end
    println("[", join(entries, ","), "]")
end

function cmd_workspace(pkgs)
    projects = String[]
    for n in toposort(pkgs)
        push!(projects, pkgs[n].path)
        isfile(joinpath(ROOT, pkgs[n].path, "test", "Project.toml")) &&
            push!(projects, pkgs[n].path * "/test")
    end
    exdir = joinpath(ROOT, "examples")
    if isdir(exdir)
        for u in sort!(readdir(exdir))
            isfile(joinpath(exdir, u, "Project.toml")) && push!(projects, "examples/$u")
        end
    end
    open(joinpath(ROOT, "Project.toml"), "w") do io
        println(io, "# Generated by `julia tools/mono.jl workspace`; do not edit by hand.")
        println(io, "# Julia >= 1.12 resolves every in-repo package and test env into one")
        println(io, "# Manifest, with in-repo packages tracked by path.")
        println(io, "[workspace]\nprojects = [")
        foreach(p -> println(io, "    \"$p\","), projects)
        println(io, "]")
    end
    println("Wrote Project.toml with $(length(projects)) workspace projects.")
end

# Uniform CPU / GPU / MPI steps per affected package, using the ClimaComms
# env-var conventions. Bespoke per-package pipelines (e.g. ClimaAtmos's
# .buildkite/pipeline.yml) are not translated here.
function cmd_buildkite(pkgs, base = "origin/main")
    affected = downstream_closure(pkgs, changed_packages(pkgs, base))
    order = filter(in(affected), toposort(pkgs))
    println("steps:")
    println("  - label: \":julia: instantiate workspace\"")
    println("    key: init")
    println(
        "    command: julia --project=. -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()'",
    )
    println("  - wait")
    for n in order
        path = pkgs[n].path
        run_ = "julia --color=yes --project=$path -e 'using Pkg; Pkg.test()'"
        println("  - group: \"$n\"")
        println("    steps:")
        println("      - label: \"$n CPU\"")
        println("        command: $run_")
        println("      - label: \"$n GPU\"")
        println("        command: $run_")
        println("        env: {CLIMACOMMS_DEVICE: CUDA}")
        println("        agents: {slurm_gpus: 1}")
        println("      - label: \"$n MPI\"")
        println("        command: srun $run_")
        println("        env: {CLIMACOMMS_CONTEXT: MPI}")
        println("        agents: {slurm_ntasks: 2}")
    end
end

# Cross-package examples: examples/<name>/{Project.toml, example.toml, run.jl}.
struct Example
    name::String
    path::String
    title::String
    summary::String
    nightly::Bool           # too slow for every PR
    timeout_minutes::Int
    deps::Vector{String}    # in-repo packages it uses
end

function load_examples(pkgs)
    dir = joinpath(ROOT, "examples")
    isdir(dir) || return Example[]
    out = Example[]
    for name in sort!(readdir(dir))
        meta = joinpath(dir, name, "example.toml")
        isfile(meta) || continue
        m = TOML.parsefile(meta)
        deps =
            keys(get(TOML.parsefile(joinpath(dir, name, "Project.toml")), "deps", Dict()))
        push!(
            out,
            Example(name, "examples/$name", m["title"], m["summary"],
                get(m, "nightly", false), get(m, "timeout_minutes", 30),
                sort!(filter(in(keys(pkgs)), collect(deps)))),
        )
    end
    return out
end

function cmd_examples(pkgs, base = "origin/main"; pr = false, list = false)
    ucs = load_examples(pkgs)
    if list
        println("| Example | What it shows | Packages | CI |")
        println("|:--|:--|:--|:--|")
        for u in ucs
            println("| [$(u.title)]($(u.path)/) | $(u.summary) | ", join(u.deps, ", "),
                " | ", u.nightly ? "nightly" : "every PR", " |")
        end
        return
    end
    changed = base == "ALL" ? Set(keys(pkgs)) : changed_packages(pkgs, base)
    affected = downstream_closure(pkgs, changed)
    files =
        base == "ALL" ? String[] :
        something(changed_files(base), String[])
    hit = filter(ucs) do u
        (pr && u.nightly) && return false
        base == "ALL" || any(in(affected), u.deps) ||
            any(f -> startswith(f, u.path * "/"), files)
    end
    println(
        "[",
        join(
            (
                "{\"name\":\"$(u.name)\",\"path\":\"$(u.path)\",\"timeout\":$(u.timeout_minutes)}"
                for u in hit
            ),
            ",",
        ),
        "]",
    )
end

# For environments kept out of the workspace (experiments/): make every
# in-repo package it loads, including transitive ones, a direct dep with a
# [sources] path, so nothing silently comes from the registry (Julia >= 1.11).
function cmd_sources(pkgs, dir)
    path = joinpath(ROOT, dir, "Project.toml")
    direct =
        filter(in(keys(pkgs)), collect(keys(get(TOML.parsefile(path), "deps", Dict()))))
    closure = Set(direct)
    stack = copy(direct)
    while !isempty(stack)
        for d in pkgs[pop!(stack)].deps
            d in closure || (push!(closure, d); push!(stack, d))
        end
    end
    names = sort!(collect(closure))
    added = setdiff(names, direct)
    lines = readlines(path)
    i = findfirst(==("[sources]"), strip.(lines))
    if i !== nothing  # regenerate [sources] wholesale
        j = findnext(l -> startswith(strip(l), "["), lines, i + 1)
        lines = vcat(lines[1:(i - 1)], j === nothing ? String[] : lines[j:end])
    end
    if !isempty(added)
        k = findfirst(==("[deps]"), strip.(lines))
        uuid(n) = TOML.parsefile(joinpath(ROOT, pkgs[n].path, "Project.toml"))["uuid"]
        splice!(lines, (k + 1):k, ["$n = \"$(uuid(n))\"" for n in added])
    end
    while !isempty(lines) && isempty(strip(lines[end]))
        pop!(lines)
    end
    push!(lines, "", "[sources]")
    for n in names
        push!(
            lines,
            "$n = {path = \"$(relpath(joinpath(ROOT, pkgs[n].path), joinpath(ROOT, dir)))\"}",
        )
    end
    write(path, join(lines, '\n') * '\n')
    isempty(added) || println("$dir: added transitive in-repo deps ", join(added, ", "))
    println("$dir: [sources] for ", length(names), " in-repo packages")
end

# Owners of an environment (example/experiment): owners of its top-level
# in-repo packages, i.e. those no other in-repo dep of it depends on.
function env_owners(pkgs, owners, dir)
    deps = filter(
        in(keys(pkgs)),
        collect(
            keys(get(TOML.parsefile(joinpath(ROOT, dir, "Project.toml")), "deps", Dict())),
        ),
    )
    below = Set{String}()
    for d in deps
        stack = copy(pkgs[d].deps)
        while !isempty(stack)
            n = pop!(stack)
            n in below || (push!(below, n); append!(stack, pkgs[n].deps))
        end
    end
    tops = sort!(filter(!in(below), deps))
    return unique!(reduce(vcat, (get(owners, t, String[]) for t in tops); init = String[]))
end

# Issue/PR triage: label by package, then route to the owning team's
# GitHub Project. Consumed by .github/workflows/triage.yml.
function write_triage(pkgs, manifest)
    teams = manifest["_teams"]
    area(label, team, paths) = (; label, team, paths)
    areas =
        [area("pkg: $n", manifest[n]["team"], ["$(pkgs[n].path)/"]) for n in toposort(pkgs)]
    push!(areas, area("dev guides", manifest["dev-guides"]["team"], ["docs/dev/"]))
    push!(areas, area("examples", "software", ["examples/"]))
    push!(
        areas,
        area("experiments", "coupler", ["experiments/", ".buildkite/experiments/"]),
    )
    push!(
        areas,
        area("infrastructure", manifest["_repo"]["team"],
            ["tools/", ".github/", ".buildkite/", "packages.toml", "Project.toml"]),
    )
    js(x::AbstractString) = "\"" * x * "\""
    js(x::Integer) = string(x)
    js(xs::Vector) = "[" * join(js.(xs), ", ") * "]"
    open(joinpath(ROOT, ".github", "triage.json"), "w") do io
        println(io, "{")
        println(io, "  \"teams\": {")
        tn = sort!(collect(keys(teams)))
        for (i, t) in enumerate(tn)
            println(
                io,
                "    $(js(t)): {\"project\": $(teams[t]["project"]), \"name\": $(js(teams[t]["name"]))}",
                i < length(tn) ? "," : "",
            )
        end
        println(io, "  },")
        println(io, "  \"areas\": [")
        for (i, a) in enumerate(areas)
            println(
                io,
                "    {\"label\": $(js(a.label)), \"team\": $(js(a.team)), \"paths\": $(js(a.paths))}",
                i < length(areas) ? "," : "",
            )
        end
        println(io, "  ]")
        println(io, "}")
    end
    mkpath(joinpath(ROOT, ".github", "ISSUE_TEMPLATE"))
    open(joinpath(ROOT, ".github", "ISSUE_TEMPLATE", "issue.yml"), "w") do io
        print(
            io,
            """
  # Generated by `julia tools/mono.jl codeowners`; do not edit.
  name: Bug report, feature request, or question
  description: Anything about a CliMA package, example, or experiment
  body:
    - type: dropdown
      id: package
      attributes:
        label: Package
        description: Which part of the repo is this about? This routes it to the owning team.
        options:
  """,
        )
        for a in areas
            println(io, "        - ", js(a.label))
        end
        print(
            io,
            """
          - "not sure"
      validations:
        required: true
    - type: dropdown
      id: kind
      attributes:
        label: Kind
        options: ["bug", "feature request", "question", "documentation"]
      validations:
        required: true
    - type: textarea
      id: description
      attributes:
        label: Description
        description: What happened, what you expected, and how to reproduce it (a minimal script if you can).
      validations:
        required: true
    - type: textarea
      id: versions
      attributes:
        label: Versions
        description: Output of `using Pkg; Pkg.status()` and `versioninfo()`.
        render: text
  """,
        )
    end
    write(
        joinpath(ROOT, ".github", "ISSUE_TEMPLATE", "config.yml"),
        "blank_issues_enabled: false\n",
    )
end

function cmd_codeowners(pkgs)
    manifest = TOML.parsefile(joinpath(ROOT, "packages.toml"))
    owners = Dict(n => get(e, "owners", String[]) for (n, e) in manifest)
    infra = owners["_repo"]
    rows = Pair{String, Vector{String}}[]
    push!(rows, "*" => infra)
    for n in toposort(pkgs)
        push!(rows, "/$(pkgs[n].path)/" => owners[n])
    end
    for (n, e) in manifest  # non-Julia subtrees, e.g. dev guides
        haskey(e, "path") && !get(e, "julia", true) &&
            push!(rows, "/$(e["path"])/" => owners[n])
    end
    for area in ("examples", "experiments"), d in sort(readdir(joinpath(ROOT, area)))
        isfile(joinpath(ROOT, area, d, "Project.toml")) || continue
        push!(rows, "/$area/$d/" => env_owners(pkgs, owners, "$area/$d"))
    end
    for p in ("/tools/", "/.github/", "/.buildkite/", "/packages.toml", "/Project.toml")
        push!(rows, p => infra)
    end
    w = maximum(length(first(r)) for r in rows) + 2
    open(joinpath(ROOT, ".github", "CODEOWNERS"), "w") do io
        println(
            io,
            "# Generated by `julia tools/mono.jl codeowners` from packages.toml; do not edit.",
        )
        println(io, "# The last matching pattern wins. See docs/OWNERSHIP.md.")
        for (pat, os) in rows
            isempty(os) && error("no owners for $pat")
            println(io, rpad(pat, w), join(os, " "))
        end
    end
    write_triage(pkgs, manifest)
    println(
        "Wrote .github/CODEOWNERS ($(length(rows)) rules), .github/triage.json, and the issue form",
    )
end

function main(args)
    isempty(args) && return println(read(@__FILE__, String) |> s -> split(s, "\n\n")[1])
    pkgs = load_packages()
    cmd, rest = args[1], args[2:end]
    flags = filter(startswith("--"), rest)
    pos = filter(!startswith("--"), rest)
    cmd == "graph" ? cmd_graph(pkgs) :
    cmd == "affected" ? cmd_affected(pkgs, pos...; docs = "--docs" in flags) :
    cmd == "compat" ? cmd_compat(pkgs, "--strict" in flags) :
    cmd == "test" ? cmd_test(pkgs, pos[1], "--registered" in flags) :
    cmd == "bump" ? cmd_bump(pkgs, pos[1], pos[2], "--release-dependents" in flags) :
    cmd == "releases" ? cmd_releases(pkgs, pos[1]) :
    cmd == "workspace" ? cmd_workspace(pkgs) :
    cmd == "buildkite" ? cmd_buildkite(pkgs, pos...) :
    cmd == "codeowners" ? cmd_codeowners(pkgs) :
    cmd == "sources" ? cmd_sources(pkgs, pos[1]) :
    cmd == "examples" ?
    cmd_examples(pkgs, pos...; pr = "--pr" in flags, list = "--list" in flags) :
    error("unknown command $cmd")
end

main(ARGS)
