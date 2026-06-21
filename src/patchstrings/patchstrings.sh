#!/bin/bash

if [[ "$1" == "--find" ]]; then
    regex="$2"
    bin="$3"

    if [[ -z "$regex" || -z "$bin" ]]; then
        echo "usage: $0 --find <regex> <binary>"
        exit 1
    fi

    if [[ ! -f "$bin" ]]; then
        echo "[error]: $bin doesn't exist"
        exit 1
    fi

    REGEX="$regex" perl -0777 -ne '
        my $r = $ENV{REGEX};
        while (/$r[^\0]*/g) {
            print "$&\n";
        }
    ' "$bin"
    exit 0
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
