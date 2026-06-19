#!/bin/bash

out_path="$1"

closure="$REF"

is_runtime() {
    grep -R -a -q "$1" "$DRV"
}

while read -r line; do
    [[ -z "$line" ]] && continue

    if is_runtime "$line"; then
        echo "$line" >>"$out_path"
    fi
done <"$closure"
