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
      copyclosure = pkgs.callPackage ./copyclosure.nix {};
      runtimedeps = pkgs.callPackage ./runtimedeps.nix {};

      hello-closure = pkgs.runCommand "hello-closure" {
        nativeBuildInputs = [
          (pkgs.copyclosure.override {
            drv = pkgs.hello;
            refs = pkgs.runtimedeps.override {
              drv = pkgs.hello;
            };
          })
        ];
      } ''copyclosure "$out"'';
    };

    overlayAttrs = {
      inherit (config.packages) patchstrings copyclosure runtimedeps;
    };
  };
}
