{
  deployTools,
  fpm,
  gnutar,
  lib,
  libarchive,
  rpm,
  runCommand,
  stdenv,
  zstd,
}: {
  drv,
  format,
  pname ? drv.pname or drv.name,
  version ? drv.version or "0.0.0",
  architecture ? stdenv.hostPlatform.parsed.cpu.name,
  installPrefix ? "/opt/${pname}",
  binDir ? "/usr/bin",
  fpmArgs ? {},
  ...
} @ args: let
  privateArgNames = [
    "drv"
    "format"
    "mode"
    "pname"
    "version"
    "architecture"
    "installPrefix"
    "binDir"
    "dependencies"
    "extraFpmArgs"
  ];
  exposedPrograms =
    if builtins.pathExists "${drv}/bin"
    then builtins.filter (path: (builtins.match "^[^./].+$" path) != null) (builtins.attrNames (builtins.readDir "${drv}/bin"))
    else [];

  packageName = builtins.elemAt (builtins.attrNames (builtins.readDir fpmbundle)) 0;

  sanitizedArgs = lib.filterAttrs (name: _: !(lib.elem name privateArgNames)) args;
  fpmArgsWithDefault =
    {
      inherit version architecture;

      provides = exposedPrograms;

      maintainer =
        if builtins.hasAttr "maintainers" drv.meta
        then
          # Ex.: Carlo <carlo@email.com>
          lib.concatStringsSep ", " (builtins.map (maintainer: "${maintainer.name} ${
              if builtins.hasAttr "email" maintainer && maintainer.email != ""
              then "<${maintainer.email}>"
              else ""
            }")
            drv.meta.maintainers)
        else "no maintainer";

      vendor = "nixpkgs by Nix-Deploy";

      url =
        if builtins.hasAttr "homepage" drv.meta
        then drv.meta.homepage
        else "no url";

      description =
        if builtins.hasAttr "description" drv.meta
        then drv.meta.description
        else "no description";

      license =
        if builtins.hasAttr "license" drv.meta
        then drv.meta.license.shortName
        else "no license";

      name = pname;
      output-type = format;
      input-type = "dir";
    }
    // fpmArgs;

  fpmOptions = lib.cli.toCommandLineShellGNU {} fpmArgsWithDefault;

  bundle = deployTools.mkBundle {inherit drv installPrefix;};

  fpmSrc =
    runCommand "${pname}-fpm-src" {}
    ''
      mkdir -p "$out${installPrefix}"
      cp -r ${bundle}/. "$out${installPrefix}/"
      chmod -R u+w "$out${installPrefix}"

      mkdir -p "$out${binDir}"
      ${lib.concatMapStringsSep "\n" (name:
        /*
        bash
        */
        ''
          if [ -e "$out${installPrefix}/bin/${name}" ]; then
            target=$(realpath --relative-to="$out${binDir}" "$out${installPrefix}/bin/${name}")
            ln -s "$target" "$out${binDir}/${name}"
          fi
        '')
      exposedPrograms}
    '';

  fpmbundle = stdenv.mkDerivation ({
      name = "fpm-bundle";
      src = fpmSrc;

      nativeBuildInputs = [
        fpm
        gnutar
        libarchive
        rpm
        zstd
      ];

      buildPhase = ''
        mkdir "fpm-bundle"
        fpm ${fpmOptions} -p fpm-bundle/ .
      '';

      installPhase = ''
        mkdir -p "$out"
        cp -r fpm-bundle/. "$out"
      '';
    }
    // sanitizedArgs);
in
  runCommand packageName {} ''
    cp ${fpmbundle}/${packageName} "$out"
  ''
