#!/bin/bash

if [[ "$1" == "--find" ]]; then
    regex="$2"
    path="$3"

    if [[ -z "$regex" || -z "$path" ]]; then
        echo "usage: $0 --find <regex> <path>"
        exit 1
    fi

    if [[ -f "$path" ]]; then
        strings "$path" | grep -Eo "$regex" | sed '/^$/d' | sort -u
        exit 1
    fi

    if [[ -d "$path" ]]; then
        find "$path" -type f -exec sh -c '
        for file do
            strings "$file" | grep -Eo "$0"
        done
    ' "$regex" {} + | sed '/^$/d' | sort -u
        exit 0
    fi

    echo "[error]: '$path' needs to be directory or file".
    exit 1
fi

old="$1"
size_old="${#old}"

new="$2"
size_new="${#new}"

bin="$3"

if ((size_old < size_new)); then
    echo '[error]: This is not valid! the new string must be equal or lower the length of the old string'
    exit 1
fi

if [[ ! -x "$bin" ]]; then
    echo "[error]: $bin doesn't exist or ins't and executable"
    exit 1
fi

perl -0777 -pi -e "s{\Q$old\E}{
    my \$r = \"$new\";
    \$r . (chr(0) x ($size_old - length(\$r)))
  }ge" "$bin"

echo "$bin: $old -> $new"
