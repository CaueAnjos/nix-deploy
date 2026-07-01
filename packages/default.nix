{inputs, ...}: {
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];

  perSystem = {
    config,
    pkgs,
    ...
  }: {
    packages = {
      inherit (pkgs) patchelf;
      patchstrings = pkgs.callPackage ./patchstrings.nix {};

      hello-closure = pkgs.runCommand "hello-closure" {
        nativeBuildInputs = [
          (pkgs.deployTools.mkCopyclosureCommand {
            drv = pkgs.hello;
            refs = pkgs.deployTools.mkRuntimeDeps pkgs.hello;
          })
        ];
      } ''copyclosure "$out"'';

      test-bundle = pkgs.deployTools.mkBundle {
        drv = pkgs.hello;
      };

      test-compact = pkgs.deployTools.mkCompactClosure pkgs.hello;
    };

    overlayAttrs = {
      inherit (config.packages) patchstrings copyclosure runtimedeps;
    };
  };
}
