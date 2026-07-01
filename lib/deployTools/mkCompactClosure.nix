{
  lib,
  references,
  symlinkJoin,
}: drv: let
  referencesFile = references drv;
  referencePaths = lib.unique (
    lib.filter (path: path != "" && lib.pathIsDirectory (builtins.storePath path))
    (lib.splitString "\n" (builtins.readFile referencesFile))
  );
in
  symlinkJoin {
    name = "${drv.pname}-closure";
    paths = referencePaths;
  }
