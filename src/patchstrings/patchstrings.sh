#!/bin/bash

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

perl -0777 -pi -e "s{$old}{
    my \$r = \"$new\";
    \$r . (\0 x ($size_old - length(\$r)))
  }ge" "$bin"

echo "$bin: $old -> $new"
