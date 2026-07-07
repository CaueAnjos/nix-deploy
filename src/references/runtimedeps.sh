#!/bin/bash
set -euo pipefail

out_path="$out"
: >"$out_path"

candidates_file="$(mktemp)"
trap 'rm -f "$candidates_file"' EXIT
grep -v '^$' "$REF" >"$candidates_file" || true

# Breadth-first search over the closure: a path is only a genuine runtime
# dependency if its string is reachable by following actual file
# references, starting from the built derivation itself. Checking every
# candidate against "$DRV" alone (the old approach) misses transitive
# runtime deps whose string only appears inside another dependency's files
# (e.g. a shared library that itself dlopen()s another shared library).
queue=("$DRV")

while ((${#queue[@]})); do
    current="${queue[0]}"
    queue=("${queue[@]:1}")

    [[ -s "$candidates_file" ]] || break

    mapfile -t found < <(grep -R -a -h -o -F -f "$candidates_file" -- "$current" 2>/dev/null | sort -u)
    ((${#found[@]})) || continue

    grep -v -F -f <(printf '%s\n' "${found[@]}") "$candidates_file" >"${candidates_file}.new" || true
    mv "${candidates_file}.new" "$candidates_file"

    for path in "${found[@]}"; do
        echo "$path" >>"$out_path"
        queue+=("$path")
    done
done

echo "$DRV" >>"$out_path"
