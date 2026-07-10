{
  inputs,
  self,
}: {
  imports = [
    inputs.flake-parts.flakeModules.easyOverlay
  ];

  perSystem = {pkgs, ...}: {
    overlayAttrs = let
      deployTools = self.lib.deployTools {inherit pkgs;};
      utilities = self.lib.utilities {inherit pkgs;};
    in {
      inherit deployTools;
      inherit (utilities) join;
    };
  };

  flake.lib = {
    utilities = {
      pkgs,
      lib ? pkgs.lib,
      system ? pkgs.system,
    }: {
      join = pkgs.callPackage ./join.nix {};
    };

    deployTools = {
      pkgs,
      lib ? pkgs.lib,
      system ? pkgs.system,
    }: {
      mkReferences = pkgs.callPackage ./deployTools/mkReferences.nix {};
      mkCompactClosure = pkgs.callPackage ./deployTools/mkCompactClosure.nix {};
      mkBundle = pkgs.callPackage ./deployTools/mkBundle.nix {};
      mkClosure = pkgs.callPackage ./deployTools/mkClosure.nix {};
      mkFpmBundle = pkgs.callPackage ./deployTools/mkFpmBundle.nix {};
    };
  };
}
