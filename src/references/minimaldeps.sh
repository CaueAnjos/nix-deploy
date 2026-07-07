#!/bin/bash
set -euo pipefail

NIX_STRING_REGEX="/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+"

out_path="$out"
: >"$out_path"

echo "$DRV" >>"$out_path"

declare -A seen_paths

is_valid_path() {
    local pattern="^$NIX_STRING_REGEX"
    if [[ -z $1 || (! -d $1 && ! -f $1) || ! $1 =~ $pattern ]]; then
        return 1
    else
        return 0
    fi
}

mark_seen_path() {
    if [[ -z $1 ]]; then
        return 0
    fi

    seen_paths["$1"]=1
}

is_seen_path() {
    [[ -v seen_paths["$1"] ]]
}

embeded_references() {
    local base_path="$1"

    local path
    while read -r path; do
        if [[ $path =~ /lib(64)?$ ]] || ! is_valid_path "$path" || is_seen_path "$path"; then
            mark_seen_path "$path"
            continue
        fi

        echo "$path"
        echo "$path" >>"$out_path"
        mark_seen_path "$path"

        if [[ -d $path ]]; then
            embeded_references "$path"
        fi
    done < <(patchstrings --find "${NIX_STRING_REGEX}[^ '"'"'":;=%+,*$]*" "$base_path")
}

echo "loking for embeded references.."
mark_seen_path "$DRV"
embeded_references "$DRV"

declare -A lib_cache

# Resolves and records the needed-library closure for a single file. This is
# intentionally NOT recursive over the filesystem (no `find` here) - it only
# ever inspects the one ELF file it's given via patchelf, and recurses via
# library_references() into any *newly discovered* library location.
process_needed_libs() {
    local item="$1"

    local rpath
    while read -r rpath; do
        if [[ ! -d $rpath ]]; then
            continue
        fi

        local needed
        while read -r needed; do
            if [[ -z $needed ]]; then
                continue
            fi

            local cache_key="$rpath|$needed"
            local location
            if [[ -v lib_cache["$cache_key"] ]]; then
                location="${lib_cache[$cache_key]}"
            else
                location="$(find "$rpath" -name "$needed" -print -quit)"
                lib_cache["$cache_key"]="$location"
            fi

            if [[ $location ]] && ! is_seen_path "$location"; then
                echo "$location"
                echo "$location" >>"$out_path"
                library_references "$location"
            fi
        done < <(patchelf --print-needed "$item" 2>/dev/null)
    done < <(patchelf --print-rpath "$item" 2>/dev/null | tr ':' '\n')
}

library_references() {
    local item="$1"

    if ! is_valid_path "$item" || is_seen_path "$item"; then
        mark_seen_path "$item"
        return 0
    fi

    mark_seen_path "$item"
    process_needed_libs "$item"

    if [[ -d $item ]]; then
        # Walk the subtree exactly once here. Do NOT recurse back into
        # library_references() for entries discovered by this find - they
        # already belong to the tree we're currently walking, so doing that
        # would re-`find` the same subtree again for every nested directory
        # (O(depth * N) instead of O(N)). Newly discovered *library*
        # locations (outside this tree) still recurse via
        # process_needed_libs -> library_references above.
        local path
        while read -r -d '' path; do
            if is_valid_path "$path" && ! is_seen_path "$path"; then
                mark_seen_path "$path"
                process_needed_libs "$path"
            fi
        done < <(find "$item" -mindepth 1 -print0)
    fi
}

echo "loking for library references..."
seen_paths=()
while read -r path; do
    library_references "$path"
done <"$out_path"

echo "deduplicating..."
sort -u -o "$out_path" "$out_path"

# Drop any path that has an ancestor directory already present in the list.
# Sorting guarantees an ancestor "$p" always sorts before any of its
# descendants "$p/..." (a strict prefix is always lexicographically
# smaller), so a single forward pass keeping a hash-set of every path kept
# so far is enough: for each path, walk up its own ancestor chain checking
# set membership (bounded by path depth, not by N) instead of re-scanning
# the whole file per entry.
tmp=$(mktemp)
declare -A kept_set
while read -r path; do
    p="$path"
    nested=0

    while [[ $p == */* ]]; do
        p="${p%/*}"
        if [[ -v kept_set["$p"] ]]; then
            nested=1
            break
        fi
    done

    if [[ $nested == 0 ]]; then
        echo "$path" >>"$tmp"
        kept_set["$path"]=1
    fi
done <"$out_path"

mv "$tmp" "$out_path"
