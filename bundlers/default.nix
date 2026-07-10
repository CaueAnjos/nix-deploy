{inputs, ...}: {
  imports = [
    inputs.flake-parts.flakeModules.bundlers
  ];

  perSystem = {pkgs, ...}: {
    bundlers = {
      toBaseBundle = drv:
        pkgs.deployTools.mkBundle {
          inherit drv;
        };

      toDeb = drv:
        pkgs.deployTools.mkFpmBundle {
          inherit drv;
          format = "deb";
        };

      toRpm = drv:
        pkgs.deployTools.mkFpmBundle {
          inherit drv;
          format = "rpm";
        };

      toPacman = drv:
        pkgs.deployTools.mkFpmBundle {
          inherit drv;
          format = "pacman";
        };
    };
  };
}
