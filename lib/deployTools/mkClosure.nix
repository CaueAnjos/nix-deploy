{
  deployTools,
  runCommand,
}: drv: let
  copyclosure = deployTools.mkCopyclosureCommand {inherit drv;};
in
  runCommand "${drv.pname}-closure"
  {nativeBuildInputs = [copyclosure];}
  ''
    copyclosure "/nix/store/$out"
  ''
