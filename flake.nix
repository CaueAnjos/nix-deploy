{
  description = "An easy way to package and deploy your software";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    systems.url = "github:nix-systems/default-linux";
  };

  outputs = inputs @ {
    flake-parts,
    self,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      imports = [
        (import ./packages {inherit inputs;})
        (import ./lib {inherit inputs self;})
        ./tests
      ];
      systems = import inputs.systems;
      perSystem = {
        pkgs,
        system,
        ...
      }: {
        _module.args.pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = with self.overlays; [
            default
          ];
        };

        devShells.default = pkgs.mkShellNoCC {
          name = "dev";
          packages = with pkgs; [
            patchelf
            patchstrings
            podman
          ];
        };
      };
    };
}
