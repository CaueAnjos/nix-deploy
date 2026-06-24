# FIX: this logic can be more configurable and explicit
{
  lib,
  references,
  symlinkJoin,
}: {
  drv,
  referenceExcludes ? {
    useDefaults = true;
    extraPatterns = [];
    extraPaths = [];
  },
}: let
  referencesFile = references drv;
  referencePaths =
    lib.filter (path: path != "")
    (lib.splitString "\n" (builtins.readFile referencesFile));
  defaultExcludePatterns = [
    "-bash-"
    "-coreutils-"
    "-less-"
  ];
  excludeConfig = referenceExcludes;
  excludePatterns = lib.unique (
    (lib.optionals (excludeConfig.useDefaults or true) defaultExcludePatterns)
    ++ (excludeConfig.extraPatterns or [])
  );
  excludePaths =
    lib.unique (map builtins.toString (excludeConfig.extraPaths or []));
  shouldExclude = path:
    (lib.elem path excludePaths)
    || lib.any (pattern: lib.hasInfix pattern (builtins.baseNameOf path)) excludePatterns;
  filteredReferencePaths = lib.filter (path: !(shouldExclude path)) referencePaths;
  closurePaths = lib.unique (
    (map (path: builtins.toPath path) filteredReferencePaths)
    ++ [drv]
  );
in
  symlinkJoin {
    name = "${drv.pname}-closure";
    paths = closurePaths;
  }
