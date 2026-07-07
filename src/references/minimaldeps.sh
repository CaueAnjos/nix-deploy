#!/bin/bash
set -euo pipefail

# ----------------------------------------------------------------------
# Required environment variables:
#   DRV - path to the derivation which will have its references searched
#
# Description:
#
#   Searches for references in two steps: `embedded_references` and
#   `library_references`. The first step (embedded_references), searches
#   for strings that match the regex:
#
#   `${NIX_STRING_REGEX}[^ '":;=%+,*$]*`
#
#   which resolves to:
#
#   `/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+[^ '":;=%+,*$]*`
#
#   All paths are added to the `$out_path` (excluding all that ends with
#   `/lib`. these are assumed to be rpaths) and recursively finds
#   `embedded_references` for the added paths.
#
#   Next step, is `library_references`. This step, finds where all
#   needed libraries are located, by matching rpath and needed object.
#
#   The final result is then deduplicated by sorting and droping any
#   path that has an ancestor directory already present in the list.
#
# Assumptions:
#
#   - The regex is able to catch all references
#   - All references that end with `/lib` or `/lib64` is an rpath
#   (normaly true)
#   - Embedded references from libraries are negligible (much closer
#   to be true, specialy if it isn't a library for interpreted langages,
#   plugins, Qt or GTK libraries)
#
#   These heuristic assumptions keep the result minimal as well as
#   unstable.
# ----------------------------------------------------------------------

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

embedded_references() {
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
            embedded_references "$path"
        fi
    done < <(patchstrings --find "${NIX_STRING_REGEX}[^ '"'"'":;=%+,*$]*" "$base_path")
}

echo "loking for embedded references.."
mark_seen_path "$DRV"
embedded_references "$DRV"

declare -A lib_cache

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
