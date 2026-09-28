using Pkg
open("specs_out.tsv", "w") do io
    for line in eachline("specs_in.tsv")
        pkg, spec, vs = split(line, '\t')
        s = try
            Pkg.Versions.semver_spec(String(spec))
        catch e
            ;
            println(stderr, "BAD ", pkg, " ", spec);
            nothing
        end
        s === nothing && continue
        ok = [v for v in split(vs, ',') if VersionNumber(v) in s]
        println(io, pkg, '\t', spec, '\t', join(ok, ','))
    end
end
