#!/usr/bin/env bash
set -euo pipefail

NIX_STRING_REGEX="/nix/store/[a-z0-9]{32}-[^'\" ]+"

: "${INTERPRETER:?INTERPRETER must be set}"
: "${INSTALL_PREFIX:?INSTALL_PREFIX must be set}"

# Interpreter is always used as-is (caller must pass an absolute path)

if [[ -n "${ABSOLUTE:-}" ]]; then
    : "${RPATH:?RPATH must be set when ABSOLUTE=1}"
    RPATH=$(realpath "$RPATH")
    echo "Mode        : absolute"
    echo "Rpath       : $RPATH"
else
    echo "Mode        : relative (\$ORIGIN-based, derived from existing nix store entries)"
    echo "Output root : $INSTALL_PREFIX"
fi
echo "Interpreter : $INTERPRETER"
echo "Prefix      : $INSTALL_PREFIX"
echo ""

find "final" -type f -print0 | parallel -0 -j8 bash "$PATCH_SCRIPT"

echo ""
echo "--- scan for leftover nix store references ---"
set +e
left_references=$(patchstrings --find "$NIX_STRING_REGEX" final/ 2>/dev/null | wc -l)
set -e

if [[ "$left_references" -eq 0 ]]; then
    echo "Clean: no nix store references remaining."
else
    echo "Warning: $left_references nix store reference(s) still present:"
    patchstrings --find "$NIX_STRING_REGEX" final/ 2>/dev/null || true
fi
