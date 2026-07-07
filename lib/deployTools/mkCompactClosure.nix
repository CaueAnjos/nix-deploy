{
  deployTools,
  symlinkJoin,
}: drv: let
  referencePaths = deployTools.mkReferences {inherit drv;};
in
  symlinkJoin {
    name = "${drv.pname}-closure";
    paths = referencePaths;
  }
