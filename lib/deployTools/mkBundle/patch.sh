#! /usr/bin/env bash

patch_elf() {
    local item="$1"

    readelf -h "$item" >/dev/null 2>&1 || return 0
    if ! readelf -S "$item" | grep -q '\.dynamic'; then
        return 0
    fi

    local elf_type
    elf_type=$(
        readelf -h "$item" |
            sed -n 's/^ *Type: *\([A-Z]*\).*/\1/p'
    )

    local old_rpath=""
    old_rpath=$(patchelf --print-rpath "$item")

    local new_rpath=""
    if [[ $ABSOLURE ]]; then
        new_rpath="$RPATH"
    else
        new_rpath=$(realpath "final/$RPATH/" --relative-to "final/lib/libc.so.6" | sed "s/\.\./\$ORIGIN/")
    fi

    case "$elf_type" in
    EXEC | DYN)
        patchelf --set-rpath "$new_rpath" "$item"
        echo "patched $item: $old_rpath -> $new_rpath"
        ;;

    *)
        echo "skipping $item ($elf_type)"
        return 0
        ;;
    esac

    if readelf -S "$item" | grep -q '\.interp'; then
        patchelf --interpreter "$INTERPRETER" "$item"
        echo "patched $item: $INTERPRETER"
    fi
}

patch_strings() {
    local item="$1"

    if [[ ! -f "$item" ]]; then
        echo "skipping $item (not a regular file)"
        return 0
    fi

    local references
    references=$(patchstrings --find "/nix/store/[a-z0-9]{32}-[^'\" ]+" "$item" 2>/dev/null || true)

    if [[ -z "$references" ]]; then
        echo "skipping $item (no nix store references)"
        return 0
    fi

    echo "patching $item"
    if file "$item" | grep -q 'text'; then
        patchstrings --text --regex 's|/nix/store/[a-z0-9]{32}-[^/]+|'"$INSTALL_PREFIX"'|g' "$item"
    else
        patchstrings --regex 's|/nix/store/[a-z0-9]{32}-[^/]+|'"$INSTALL_PREFIX"'|g' "$item"
    fi
}

patch() {
    local item="$1"
    patch_elf "$item"
    patch_strings "$item"
}

while read -r file; do
    patch "$file"
done < <(find "final" -type f)

echo "Using interpreter '$INTERPRETER'"

if [[ $ABSOLUTE ]]; then
    echo "Using rpath '$RPATH' absolute"
else
    echo "Using rpath '$RPATH' relative"
fi

set +e
left_references=$(
    patchstrings --find "/nix/store/[a-z0-9]{32}-[^'\" ]+" final/ |
        tr ':' '\n' |
        wc -c
)
echo "Ended with $left_references nix store references left"
set -e
