{
  lib,
  deployTools,
  runCommand,
}: drv: let
  references = deployTools.mkReferences {
    inherit drv;
    mode = "full";
  };

  cpCommands = lib.forEach references (reference: ''
    cp -r '${reference}' "$out/nix/store"
  '');
in
  runCommand "${drv.pname}-closure"
  {}
  ''
    mkdir -p "$out/nix/store"

    ${lib.concatLines cpCommands}
  ''
