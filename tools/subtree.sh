#!/usr/bin/env bash
# Add or sync the subtrees listed in packages.toml.
#
#   tools/subtree.sh add  [NAME...]   # first-time import (squashed)
#   tools/subtree.sh pull [NAME...]   # sync from upstream (squashed)
#   tools/subtree.sh list
#
# With no NAME, operates on every entry. Upstream is still the source of
# truth during the evaluation; once a package moves here for real, drop its
# `upstream` and stop pulling.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

entries() {
    python3 - "$@" <<'PY'
import sys, tomllib
d = tomllib.load(open("packages.toml", "rb"))
want = sys.argv[1:]
for name, e in d.items():
    if (want and name not in want) or "upstream" not in e:
        continue
    print(name, e["path"], e["upstream"], e.get("branch", "main"))
PY
}

cmd=${1:-}; shift || true
case "$cmd" in
list) entries "$@" ;;
add | pull)
    entries "$@" | while read -r name path url branch; do
        if [[ $cmd == add && -d $path ]]; then
            echo "skip $name: $path exists"; continue
        fi
        echo "==> $cmd $name ($url $branch) -> $path"
        git subtree "$cmd" --prefix "$path" "$url" "$branch" --squash \
            -m "chore($name): $cmd subtree from $url@$branch" ||
            [[ $cmd == pull ]] # pull errors when upstream has nothing new
    done
    ;;
*) sed -n '2,10p' "$0"; exit 1 ;;
esac
