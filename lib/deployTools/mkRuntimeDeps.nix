{
  runCommand,
  writeShellApplication,
  referencesByPopularity,
}: drv: let
  get-runtimedeps = writeShellApplication {
    name = "get-runtimedeps";
    runtimeEnv = {
      DRV = drv;
      REF = referencesByPopularity drv;
    };
    text = builtins.readFile ../../src/runtimedeps/runtimedeps.sh;
  };
in
  runCommand "runtimedeps" {
    nativeBuildInputs = [get-runtimedeps];
  }
  ''
    get-runtimedeps "$out"
  ''
