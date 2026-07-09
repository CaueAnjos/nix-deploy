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

      test-closure = pkgs.deployTools.mkClosure pkgs.hello;
      test-bundle = pkgs.deployTools.mkBundle {
        drv = pkgs.hello;
      };
      test-compact = pkgs.deployTools.mkCompactClosure pkgs.hello;
      test-references = pkgs.deployTools.mkReferences {
        drv = pkgs.hello;
        mode = "minimal";
        output = "file";
      };
    };

    overlayAttrs = {
      inherit (config.packages) patchstrings;
    };
  };
}
