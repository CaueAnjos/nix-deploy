#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Required environment variables:
#   INTERPRETER    - path to the ELF interpreter (ld-linux, etc.) — always
#                    resolved to an absolute path before use
#   INSTALL_PREFIX - replacement root for /nix/store/<hash>-<name> in strings
#                    and used as the absolute target tree root for $ORIGIN
#                    computation in relative mode
#
# Mode (mutually exclusive intent):
#   ABSOLUTE=1     - set rpath entries to $RPATH (must also set RPATH)
#   (unset)        - compute $ORIGIN-relative paths from each nix store
#                    entry's subpath, rooted at $INSTALL_PREFIX in the output
#                    tree; $RPATH is not used in this mode
#
# Optional (absolute mode only):
#   RPATH          - absolute rpath to stamp on every ELF (ABSOLUTE mode)
# ---------------------------------------------------------------------------

NIX_STRING_REGEX="/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+"
NIX_STORE_REGEX="(?:${NIX_STRING_REGEX})+"

# ---------------------------------------------------------------------------
# patch_elf <file>
#
# - Skips non-ELF and non-dynamic files
# - Only patches EXEC and DYN types
# - Computes new rpath per entry:
#     absolute mode : every nix store entry → $RPATH
#     relative mode : every nix store entry → $ORIGIN/<rel to subpath in output tree>
#   Non-nix entries are kept as-is. Result is deduplicated.
# - Sets interpreter (absolute) only when .interp section is present
# ---------------------------------------------------------------------------
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

            if [[ "$entry" =~ ^/nix/store/[a-z0-9]{32}-[^/]+(/.*)?$ ]]; then
                if [[ -n "${ABSOLUTE:-}" ]]; then
                    # Absolute mode: stamp the configured RPATH directly
                    new_entry="$RPATH"
                else
                    # Relative mode: derive $ORIGIN path from the subpath that
                    # follows the nix store package root in this entry.
                    #
                    # Example:
                    #   entry    = /nix/store/abc...-glibc-2.38/lib
                    #   subpath  = /lib
                    #   item     = final/bin/foo
                    #   target   = final/lib  (where the lib actually lives during build)
                    #   relative = ../lib  (from final/bin/ to final/lib)
                    #   result   = $ORIGIN/../lib
                    local subpath="${BASH_REMATCH[1]}" # may be empty for pkg root
                    local item_dir
                    item_dir=$(dirname "$item")
                    local target_abs="final${subpath}"
                    local rel
                    rel=$(realpath --relative-to="$item_dir" "$target_abs" 2>/dev/null ||
                        echo "${subpath#/}")
                    new_entry="\$ORIGIN/${rel}"
                fi
            else
                # Non-nix entry (system path, existing $ORIGIN entry, etc.): keep
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

    # Fallback: binary had no rpath at all
    if [[ -z "$new_rpath" ]]; then
        if [[ -n "${ABSOLUTE:-}" ]]; then
            new_rpath="$RPATH"
        else
            echo "warning: $item had no rpath and ABSOLUTE is not set — skipping rpath patch"
            # still continue to handle interpreter below
        fi
    fi

    if [[ -n "$new_rpath" ]]; then
        patchelf --set-rpath "$new_rpath" "$item"
        echo "patched rpath $item:"
        echo "  old: ${old_rpath:-(empty)}"
        echo "  new: $new_rpath"
    fi

    # ------------------------------------------------------------------
    # Interpreter — always absolute, only when .interp section exists
    # ------------------------------------------------------------------
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
# Binary files: slash-padded replacement (offsets stay stable, size does not
# change). We explicitly use --pad-str '/' instead of the default NUL fill:
# NUL padding corrupts strings for runtimes that store an explicit string
# length instead of relying on NUL-termination (e.g. Perl SVs, Ruby
# RStrings) — such readers happily read past the intended end of the
# shortened path and pick up the raw NUL bytes as part of the string,
# breaking module/library lookups. Padding with "/" instead keeps the
# patched bytes entirely printable and the extra path separators are
# semantically harmless for directory-style paths.
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
        patchstrings --pad-str '/' --regex "s|${NIX_STORE_REGEX}|${INSTALL_PREFIX}|g" "$item"
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
