#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Required environment variables:
#   INTERPRETER    - path to the ELF interpreter (ld-linux, etc.) — always
#                    resolved to an absolute path before use
#   INSTALL_PREFIX - replacement root for /nix/store/<hash>-<name> in strings
#                    and used as the absolute target tree root for $ORIGIN
#                    computation in relative mode
# ---------------------------------------------------------------------------

NIX_STRING_REGEX="/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+"
NIX_STORE_REGEX="(?:${NIX_STRING_REGEX})+"

# ---------------------------------------------------------------------------
# patch_elf <file>
#
# - Skips non-ELF and non-dynamic files
# - Only patches EXEC and DYN types
# - Computes new rpath per entry:
#     relative mode : every nix store entry → $INSTALL_PREFIX/<subpath in output tree>
#   Non-nix entries are kept as-is. Result is deduplicated.
# - Sets interpreter (absolute) only when .interp section is present ---------------------------------------------------------------------------
patch_elf() {
    local item
    item=$(realpath "$1")

    readelf -h "$item" >/dev/null 2>&1 || return 0
    readelf -S "$item" | grep -q '\.dynamic' || return 0

    local elf_type
    elf_type=$(readelf -h "$item" | sed -n 's/^ *Type: *\([A-Z]*\).*/\1/p')

    case "$elf_type" in
    EXEC | DYN) ;;
    *)
        echo "skipping $item (ELF type $elf_type)"
        return 0
        ;;
    esac

    # ------------------------------------------------------------------
    # Rpath: process each existing entry individually
    # ------------------------------------------------------------------
    local old_rpath
    old_rpath=$(patchelf --print-rpath "$item" 2>/dev/null || true)

    local new_rpath=""

    if [[ -n "$old_rpath" ]]; then
        local seen_paths=()
        local entry new_entry

        while IFS= read -r entry; do
            [[ -z "$entry" ]] && continue

            local pattern="$NIX_STRING_REGEX/?(.*)"

            if [[ "$entry" =~ $pattern ]]; then
                local subpath="${BASH_REMATCH[1]}"
                new_entry="$INSTALL_PREFIX/$subpath"
            else
                new_entry="$entry"
            fi

            # Deduplicate
            local dup=0 p
            for p in "${seen_paths[@]+"${seen_paths[@]}"}"; do
                [[ "$p" == "$new_entry" ]] && {
                    dup=1
                    break
                }
            done
            [[ $dup -eq 0 ]] && seen_paths+=("$new_entry")

        done < <(tr ':' '\n' <<<"$old_rpath")

        local IFS=':'
        new_rpath="${seen_paths[*]+"${seen_paths[*]}"}"
    fi

    if [[ -n "$new_rpath" ]]; then
        patchelf --set-rpath "$new_rpath" "$item"
        echo "patched rpath $item:"
        echo "  old: ${old_rpath:-(empty)}"
        echo "  new: $new_rpath"
    fi

    if readelf -S "$item" | grep -q '\.interp'; then
        patchelf --set-interpreter "$INTERPRETER" "$item"
        echo "patched interpreter $item: $INTERPRETER"
    fi
}

# ---------------------------------------------------------------------------
# patch_strings <file>
#
# Replaces nix store path prefixes with $INSTALL_PREFIX.
# Text files: --text mode (no padding, size may change).
# Binary files: slash-filled replacement (offsets stay stable, size does not
# change). We explicitly use --fill-str '/' instead of the default NUL fill:
# NUL padding corrupts strings for runtimes that store an explicit string
# length instead of relying on NUL-termination (e.g. Perl SVs, Ruby
# RStrings) — such readers happily read past the intended end of the
# shortened path and pick up the raw NUL bytes as part of the string,
# breaking module/library lookups. Filling with "/" instead keeps the
# patched bytes entirely printable and the extra path separators are
# semantically harmless for directory-style paths.
#
# --fill-str (rather than --pad-str) matters here specifically because
# NIX_STORE_REGEX matches one-or-more CONCATENATED store paths with no
# separator between them: --fill-str closes each match's gap locally, right
# after its own replacement, preserving the boundary with whatever
# immediately follows (the next store-path reference, or an unrelated
# suffix) instead of accumulating all the slack at the tail of the whole
# enclosing string.
# ---------------------------------------------------------------------------
patch_strings() {
    local item
    item=$(realpath "$1")

    if [[ ! -f "$item" ]]; then
        echo "skipping $item (not a regular file)"
        return 0
    fi

    local references
    references=$(patchstrings --find "$NIX_STRING_REGEX" "$item" 2>/dev/null || true)

    if [[ -z "$references" ]]; then
        echo "skipping $item (no nix store string references)"
        return 0
    fi

    echo "patching strings $item"
    if file "$item" | grep -q 'text'; then
        patchstrings --text --regex "s|${NIX_STORE_REGEX}|${INSTALL_PREFIX}|g" "$item"
    else
        patchstrings --fill-str '/' --regex "s|${NIX_STORE_REGEX}|${INSTALL_PREFIX}|g" "$item"
    fi
}

# ---------------------------------------------------------------------------
# patch_file <file> — runs both passes
# ---------------------------------------------------------------------------
patch_file() {
    local item="$1"
    patch_elf "$item"
    patch_strings "$item"
}

patch_file "$1"
