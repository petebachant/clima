# Monorepo helper. Stdlib only, so it runs before anything is instantiated.
#
#   julia tools/mono.jl graph                     # packages in dependency order
#   julia tools/mono.jl affected [BASE]           # changed pkgs + everything downstream (JSON)
#   julia tools/mono.jl compat [--strict]         # in-repo compat drift report
#   julia tools/mono.jl test PKG [--registered]   # test PKG against in-repo HEAD of its deps
#   julia tools/mono.jl bump PKG LEVEL            # LEVEL = major|minor|patch; widens dependents' compat
#   julia tools/mono.jl releases BASE             # pkgs whose version changed since BASE (JSON)
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

function load_packages()
    manifest = TOML.parsefile(joinpath(ROOT, "packages.toml"))
    raw = Dict{String, Tuple{String, Dict}}()
    for (name, entry) in manifest
        get(entry, "julia", true) || continue
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

function changed_packages(pkgs, base)
    files = split(git("diff", "--name-only", "$base...HEAD"), '\n'; keepempty = false)
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
    "[" * join(("{\"package\":\"$n\",\"path\":\"$(pkgs[n].path)\"}" for n in names), ",") * "]"

# ---------------------------------------------------------------------------

function cmd_graph(pkgs)
    rev = dependents(pkgs)
    for n in toposort(pkgs)
        p = pkgs[n]
        println(rpad("$n v$(p.version)", 32), "deps: ", join(p.deps, ", "))
        isempty(rev[n]) || println(" "^32, "used by: ", join(sort(rev[n]), ", "))
    end
end

function cmd_affected(pkgs, base = "origin/main")
    order = toposort(pkgs)
    affected = downstream_closure(pkgs, changed_packages(pkgs, base))
    println(json_matrix(pkgs, filter(in(affected), order)))
end

function compat_drift(pkgs)
    drift = Tuple{String, String, String, VersionNumber}[]
    for p in values(pkgs), d in unique!(vcat(p.deps, p.weakdeps))
        spec = get(p.compat, d, nothing)
        v = pkgs[d].version
        if spec === nothing || !(v in Pkg.Versions.semver_spec(spec))
            push!(drift, (p.name, d, something(spec, "<missing>"), v))
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
    println("Testing $name against ", registered ? "registered deps" :
        "in-repo HEAD of: " * (isempty(ups) ? "(none)" : join(ups, ", ")))
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
isbreaking(old, new) = old.major == 0 ? new.minor != old.minor || new.major != 0 :
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

function cmd_bump(pkgs, name, level)
    p = pkgs[name]
    new = bump(p.version, level)
    edit_project(joinpath(ROOT, p.path, "Project.toml")) do section, l
        section == "" && startswith(l, "version") ? "version = \"$new\"" : l
    end
    println("$name: $(p.version) -> $new")
    isbreaking(p.version, new) || return
    # Breaking: widen every in-repo dependent's compat in the same change.
    for q in values(pkgs)
        name in q.deps || name in q.weakdeps || continue
        haskey(q.compat, name) || continue
        spec = q.compat[name]
        new in Pkg.Versions.semver_spec(spec) && continue
        widened = "$spec, $(compat_entry(new))"
        edit_project(joinpath(ROOT, q.path, "Project.toml")) do section, l
            section == "compat" && occursin(Regex("^\\s*$name\\s*="), l) ?
                "$name = \"$widened\"" : l
        end
        println("  $(q.name): compat $name \"$spec\" -> \"$widened\"  (run its tests!)")
    end
end

function cmd_releases(pkgs, base)
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
    println(json_matrix(pkgs, out))
end

function main(args)
    isempty(args) && return println(read(@__FILE__, String) |> s -> split(s, "\n\n")[1])
    pkgs = load_packages()
    cmd, rest = args[1], args[2:end]
    flags = filter(startswith("--"), rest)
    pos = filter(!startswith("--"), rest)
    cmd == "graph" ? cmd_graph(pkgs) :
    cmd == "affected" ? cmd_affected(pkgs, pos...) :
    cmd == "compat" ? cmd_compat(pkgs, "--strict" in flags) :
    cmd == "test" ? cmd_test(pkgs, pos[1], "--registered" in flags) :
    cmd == "bump" ? cmd_bump(pkgs, pos[1], pos[2]) :
    cmd == "releases" ? cmd_releases(pkgs, pos[1]) :
    error("unknown command $cmd")
end

main(ARGS)
