{
  deployTools,
  lib,
  patchelf,
  patchstrings,
  runCommand,
  stdenv,
}: {
  drv,
  pname ? "${drv.pname}-bundled",
  version ? drv.version,
  drvLibPath ? "lib",
  installPrefix ? "/usr/${drv.pname}",
  interpreter ?
    if stdenv.is64bit
    then "/lib64/ld-linux-x86-64.so.2"
    else "/lib/ld-linux.so.2",
  libPath ?
    if stdenv.is64bit
    then "/lib64"
    else "/lib",
  algorithm ? "self-contained",
}:
lib.warnIfNot stdenv.isLinux
''
  Right now, pkgs.deployTools.mkBundle is intended to be use for Linux only.
''
(stdenv.mkDerivation {
  inherit pname version;

  src = deployTools.mkClosure drv;

  nativeBuildInputs = [
  ];

  configurePhase = ''
    cp -r "${drv}" "final"
    cp "${deployTools.references drv}" "references.txt"
  '';

  buildPhase = ''

  '';

  installPhase = ''
    # cp -r "final" "$out"
    cp -r . "$out"
  '';
})
