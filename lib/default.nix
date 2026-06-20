{self}: {
  flake.overlays.lib = pkgs: _: {
    deployTools = self.lib.deployTools {inherit pkgs;};
  };

  flake.lib.deployTools = {
    pkgs,
    lib ? pkgs.lib,
    system ? pkgs.system,
  }: {
    mkBundle = pkgs.callPackage ./deployTools/mkBundle.nix {};
  };
}
