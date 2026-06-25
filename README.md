# Nix-Deploy

<!--toc:start-->

- [Nix-Deploy](#nix-deploy)
  - [Overall Structure](#overall-structure)
  - [How Nix-Deploy Deals with Relocation](#how-nix-deploy-deals-with-relocation)
    - [The `mkBundle` Standard](#the-mkbundle-standard)
  - [Handy Tools](#handy-tools)

<!--toc:end-->

> An easy way to package and deploy your software as RPM, DEB, AppImage, Windows
> installers, and more.

## Overall Structure

**Nix-Deploy** is divided into `deployTools` (exposed as `pkgs.deployTools`),
which contains all functions needed to create deployable bundles, and `packages`
(exposed as regular `pkgs`), which delivers some handy tools for _relocation_.

The most noticeable `deployTools` is `deployTools.mkBundle`. It creates a
bundle, patching all references of the derivation closure.

```nix
pkgs.deployTools.mkBundle {
    drv = your-derivation;
    installPrefix = "/opt/${your-derivation.pname}";
}
```

> [!TIP]
> You should add the default overlay to use `deployTools` like that

## How Nix-Deploy Deals with Relocation

> [!IMPORTANT]
> This is very important! Read it with careful.

**Nix-Deploy** doesn't obligate users to use a specific standard. You can
develop your on logic using the handy tools delivered by this project. But,
`mkBundle` have a standard. If you are planning to use it, please read about its
standards.

### The `mkBundle` Standard

`mkBundle` is a build helper that aims to facilitate the creation of system
specific bundles. It is intended to be the base bundle, which will prepare you
application to be bundled again for a specific format.

In essence, `mkBundle` iterates over the derivation _references_, patches all
references to it and compact the references in one single derivation. `mkBundle`
assembles its payload through `deployTools.mkCompactClosure`, which prunes the
bundle closure using a small set of filters.

Advanced users may replace the helper entirely by overriding the
`compactClosure` attribute; `mkBundle` will respect the provided derivation and
skip its internal helper wiring.

The default algorithm for `buildPhase` will search for references to the
`/nix/store/` and patch then to `$INSTALL_PREFIX`, which can be set by the
`installPrefix` attribute.

> [!IMPORTANT]
> Every reference will remain absolute after patch! This is more reproducible.

It is also possible to override the default `buildPhase`, `installPhase`,
`configurePhase` and so on.

## Handy Tools

- `patchelf`: used to patch interpreter and `rpath`
- `patchstrings`: used to patch strings inside binaries (length of the new
  string should be lower or equal to the old string)
- `copyclosure`: used to make a copy of the closure
