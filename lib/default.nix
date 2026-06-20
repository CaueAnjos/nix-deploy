{
  inputs,
  self,
}: {
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];

  perSystem = {pkgs, ...}: {
    overlayAttrs = {
      deployTools = self.lib.deployTools {inherit pkgs;};
    };
  };

  flake.lib = {
    deployTools = {
      pkgs,
      lib ? pkgs.lib,
      system ? pkgs.system,
    }: {
      mkBundle = pkgs.callPackage ./deployTools/mkBundle.nix {};
      mkRuntimeDeps = pkgs.callPackage ./deployTools/mkRuntimeDeps.nix {};

      mkCopyclosureCommand = pkgs.callPackage ./deployTools/copyclosure.nix {};
    };
  };
}
