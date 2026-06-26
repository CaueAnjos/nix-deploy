{
  deployTools,
  lib,
  parallel,
  patchelf,
  patchstrings,
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
  rpath ? "/lib",
  referenceExcludes ? {
    useDefaults = true;
    extraPatterns = [];
    extraPaths = [];
  },
  patchScript ? ./mkBundle/patch.sh,
  absolute ? false,
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

      INSTALL_PREFIX = installPrefix;
      INTERPRETER = interpreter;
      RPATH = rpath;
      ABSOLUTE = absolute;

      PATCH_SCRIPT = patchScript;

      nativeBuildInputs = [
        parallel
        patchelf
        patchstrings
      ];

      configurePhase = ''
        chmod -R a+w "nix"
        cp -r -L "${compactClosure}" "final"
        chmod -R a+w "final"
      '';

      dontFixup = true;

      buildPhase = builtins.readFile ./mkBundle/default_build.sh;

      installPhase = ''
        chmod -R a-w "final"
        cp -r "final" "$out"
      '';
    }
    // sanitizedArgs))
