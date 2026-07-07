{
  referencesByPopularity,
  runCommand,
}: {
  drv,
  reverse ? false, # output order
  mode ? "runtime", # defaults to popularity
  output ? "nix",
}: let
  perMode = {
    runtime =
      runCommand "runtime" {
        nativeBuildInputs = [];
        DRV = drv;
        REF = referencesByPopularity drv;
      }
      (builtins.readFile ./../../src/references/runtimedeps.sh);

    full = referencesByPopularity drv;
  };

  perOutput = {
    nix = final:
      lib.unique (
        lib.filter (path: path != "")
        (lib.splitString "\n" (builtins.readFile final))
      );

    file = final: final;
  };

  validModes = builtins.attrNames perMode;
  validOutputs = builtins.attrNames perOutput;

  primary =
    if (!builtins.elem mode validModes)
    then throw "unkown `${mode}` mode. Use: minimal, runtime or full instead."
    else perMode.${mode};

  final =
    if reverse
    then
      runCommand "${primary.name}-reversed" {} ''
        tac ${primary} > $out
      ''
    else primary;

  result =
    if (!builtins.elem output validOutputs)
    then throw "unkown `${output}` output. Use: nix or file instead."
    else perOutput.${output} final;
in
  result
