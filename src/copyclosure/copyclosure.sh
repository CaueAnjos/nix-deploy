#!/bin/bash

out_path="$1"
mkdir -p "$out_path"

closure="$REF"

while read -r line; do
    [[ -z "$line" ]] && continue

    if [[ "$line" != "$DRV" ]]; then
        item="$out_path/${line##*/}"
        cp -r "$line" "$item"
    fi
done <"$closure"
