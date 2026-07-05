{
  deployTools,
  lib,
  parallel,
  patchelf,
  patchstrings,
  rsync,
  stdenv,
}: {
  drv,
  pname ? "${drv.pname}-bundled",
  version ? drv.version,
  installPrefix ? "/opt/${drv.pname}",
  interpreter ?
    if stdenv.is64bit
    then "${installPrefix}/lib64/ld-linux-x86-64.so.2"
    else "${installPrefix}/lib/ld-linux.so.2",
  patchScript ? ./mkBundle/patch.sh,
  compactClosure ? deployTools.mkCompactClosure drv,
  ...
} @ args: let
  privateArgNames = ["drv" "compactClosure"];
  sanitizedArgs = lib.filterAttrs (name: _: !(lib.elem name privateArgNames)) args;
in
  lib.warnIfNot stdenv.isLinux
  ''
    Right now, pkgs.deployTools.mkBundle is intended to be use for Linux only.
  ''
  (stdenv.mkDerivation ({
      inherit pname version;
      src = compactClosure;

      INSTALL_PREFIX = installPrefix;
      INTERPRETER = interpreter;

      PATCH_SCRIPT = patchScript;

      nativeBuildInputs = [
        parallel
        patchelf
        patchstrings
        rsync
      ];

      unpackPhase = ''
        mkdir -p "src"
        rsync -a -L "$src/." "src" || {
          status=$?
          # rsync exits 23 ("partial transfer due to error") when it hits a
          # broken/dangling symlink with --copy-links; it still skips that
          # entry and copies everything else, so treat it as non-fatal.
          if [ "$status" -ne 23 ]; then
            exit "$status"
          fi
        }
        chmod -R u+w "src"
        cd "src"
      '';

      dontFixup = true;

      buildPhase = builtins.readFile ./mkBundle/default_build.sh;

      installPhase = ''
        chmod -R u-w .
        cp -r . "$out"
      '';
    }
    // sanitizedArgs))
