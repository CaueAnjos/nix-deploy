{
  perSystem = {
    pkgs,
    lib,
    ...
  }: let
    mkProgram = name: desc: runtimeInputs: text: rec {
      inherit name desc;
      script = pkgs.writeShellApplication {
        inherit name runtimeInputs text;
      };
    };

    mkApp = {
      desc,
      script,
      ...
    }: {
      program = lib.getExe script;
      meta.description = desc;
    };

    programs = {
      hello =
        mkProgram "say-hello"
        "Says hellow with a cow!" [
          pkgs.cowsay
        ]
        (builtins.readFile ./say-hello.bash);
    };
  in {
    apps = {
      "hello" = mkApp programs.hello;
    };
  };
}
