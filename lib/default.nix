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
      mkReferences = pkgs.callPackage ./deployTools/mkReferences.nix {};
      mkCompactClosure = pkgs.callPackage ./deployTools/mkCompactClosure.nix {};
      mkBundle = pkgs.callPackage ./deployTools/mkBundle.nix {};
      mkClosure = pkgs.callPackage ./deployTools/mkClosure.nix {};
      mkCopyclosureCommand = pkgs.callPackage ./deployTools/copyclosure.nix {};
    };
  };
}
