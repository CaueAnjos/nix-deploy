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
      # FIX: possibly need to rewrite
      mkRuntimeDeps = pkgs.callPackage ./deployTools/mkRuntimeDeps.nix {};
      mkClosure = pkgs.callPackage ./deployTools/mkClosure.nix {};
      mkCopyclosureCommand = pkgs.callPackage ./deployTools/copyclosure.nix {};

      references = pkgs.callPackage ./deployTools/references.nix {};
    };
  };
}
