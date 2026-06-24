{
  deployTools,
  lib,
  patchelf,
  patchstrings,
  stdenv,
}: {
  drv,
  pname ? "${drv.pname}-bundled",
  version ? drv.version,
  installPrefix ? "/usr/${drv.pname}",
  interpreter ?
    if stdenv.is64bit
    then "/lib64/ld-linux-x86-64.so.2"
    else "/lib/ld-linux.so.2",
  rpath ? "/lib",
  referenceExcludes ? {
    useDefaults = true;
    extraPatterns = [];
    extraPaths = [];
  },
  absoluteReferences ? false,
  compactClosure ?
    deployTools.mkCompactClosure {
      inherit drv referenceExcludes;
    },
  ...
} @ args: let
  privateArgNames = ["drv" "referenceExcludes" "compactClosure"];
  sanitizedArgs = lib.filterAttrs (name: _: !(lib.elem name privateArgNames)) args;
in
  lib.warnIfNot stdenv.isLinux
  ''
    Right now, pkgs.deployTools.mkBundle is intended to be use for Linux only.
  ''
  (stdenv.mkDerivation ({
      inherit pname version;
      src = deployTools.mkClosure drv;

      nativeBuildInputs = [
        patchelf
        patchstrings
      ];

      configurePhase = ''
        chmod -R a+w "nix"
        cp -r -L "${compactClosure}" "final"
        chmod -R a+w "final"
      '';

      dontFixup = true;

      buildPhase = ''
        patch() {
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

            local old_rpath=$(patchelf --print-rpath "$item")
            local new_rpath="${
          if absoluteReferences
          then rpath
          else "$(realpath 'final/${rpath}/' --relative-to 'final/lib/libc.so.6' | sed 's/\.\./$ORIGIN/')"
        }"

            case "$elf_type" in
                EXEC|DYN)
                    patchelf --set-rpath "$new_rpath" "$item"
                    echo "patched $item: $old_rpath -> $new_rpath"
                    ;;

                *)
                    echo "Skipping $item ($elf_type)"
                    return 0
                    ;;
            esac

            if readelf -S "$item" | grep -q '\.interp'; then
                patchelf --interpreter '${interpreter}' "$item"
                echo "patched $item: ${interpreter}"
            fi
        }

        while read -r file; do
            patch "$file"
        done < <(find "final" -type f)
      '';

      installPhase = ''
        chmod -R a-w "final"
        cp -r "final" "$out"
      '';
    }
    // sanitizedArgs))
