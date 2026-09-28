#!/usr/bin/env bash
# Ask Registrator to register every package whose version changed between
# BASE and HEAD, in dependency order.
#
#   tools/register.sh BASE [--dry-run]
#
# Before commenting for a package, waits until the new versions of its
# in-repo deps from the same push are in General. Otherwise AutoMerge
# rejects the dependent because its compat can't be satisfied yet.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

base=$1
dry=${2:-}
sha=$(git rev-parse HEAD)
repo=${GITHUB_REPOSITORY:-CliMA/clima}
timeout_min=${REGISTER_TIMEOUT_MIN:-120}

in_general() { # NAME VERSION
    curl -fsSL "https://raw.githubusercontent.com/JuliaRegistries/General/master/${1:0:1}/$1/Versions.toml" 2>/dev/null |
        grep -qF "[\"$2\"]"
}

julia tools/mono.jl releases "$base" | python3 -c '
import json, sys
for p in json.load(sys.stdin):
    print(p["package"], p["path"], p["version"], " ".join(p["waits_for"]))
' | while read -r name path version waits; do
    for w in $waits; do
        dep=${w%@*} v=${w#*@}
        echo "  $name waits for $dep $v in General"
        [[ $dry == --dry-run ]] && continue
        deadline=$((SECONDS + timeout_min * 60))
        until in_general "$dep" "$v"; do
            ((SECONDS < deadline)) || { echo "timed out waiting for $dep $v"; exit 1; }
            sleep 60
        done
    done
    body="@JuliaRegistrator register subdir=$path branch=main"
    echo "==> $name $version: $body"
    [[ $dry == --dry-run ]] || gh api "repos/$repo/commits/$sha/comments" -f body="$body" >/dev/null
done
