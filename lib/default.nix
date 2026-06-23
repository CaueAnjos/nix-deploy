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
    }: let
      deployTools = rec {
        references = pkgs.callPackage ./deployTools/references.nix {};
        mkCompactClosure = pkgs.callPackage ./deployTools/mkCompactClosure.nix {
          inherit references;
        };
        mkBundle = pkgs.callPackage ./deployTools/mkBundle.nix {
          inherit deployTools;
        };
        # FIX: possibly need to rewrite
        mkRuntimeDeps = pkgs.callPackage ./deployTools/mkRuntimeDeps.nix {};
        mkClosure = pkgs.callPackage ./deployTools/mkClosure.nix {
          inherit deployTools;
        };
        mkCopyclosureCommand = pkgs.callPackage ./deployTools/copyclosure.nix {};
      };
    in
      deployTools;
  };
}
