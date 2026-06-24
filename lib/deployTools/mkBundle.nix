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
  INSTALL_PREFIX ? "/usr/${drv.pname}",
  INTERPRETER ?
    if stdenv.is64bit
    then "/lib64/ld-linux-x86-64.so.2"
    else "/lib/ld-linux.so.2",
  RPATH ? "/lib",
  referenceExcludes ? {
    useDefaults = true;
    extraPatterns = [];
    extraPaths = [];
  },
  ABSOLUTE ? false,
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
      inherit INSTALL_PREFIX INTERPRETER RPATH ABSOLUTE;

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

      buildPhase = builtins.readFile ./mkBundle/patch.sh;

      installPhase = ''
        chmod -R a-w "final"
        cp -r "final" "$out"
      '';
    }
    // sanitizedArgs))
