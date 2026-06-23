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

**Nix-Deploy** is divided into `lib.deployTools`, which contains all functions
needed to create deployable bundles, and `package`, which delivers some handy
tools for _relocation_.

The most noticeable `lib.deployTools` is `lib.deployTools.mkBundle`. It creates
a bundle, patching all references of the derivation closure.

```nix
lib.deployTools.mkBundle {
    drv = your-derivation;
    style = "self-contained";
    libPath = "lib";
    installPrefix = "/opt/${your-derivation.pname}";
}
```

- `self-contained` uses relative paths for "every" reference. So the `rpath` is
  set to `"$ORIGIN/../${libPath}`, or something similar. This permits the
  software to be easily relocated. Works most of the time. The only case where
  this won't work is when it needs to patch strings inside binaries. In most
  cases this won't make the software runnable unless installed at the
  `installPrefix`, because the references will be relocated expecting that path.
- `system-trust` expects that all libraries will be at `/usr/lib64`. This
  requires you to guarantee that these libs will be there. With **Nix-Deploy**
  this isn't too hard. It will put all libs needed for your application inside
  `libPath`, you will just need to copy then or use other method, like requiring
  it inside the package as a dependency.

## How Nix-Deploy Deals with Relocation

This is very important! Read it with careful.

**Nix-Deploy** doesn't obligate users to use a specific standard. You can
develop your on logic using the handy tools delivered by this project. But,
`mkBundle` have a standard. If you are planning to use it, please read about its
standards.

### The `mkBundle` Standard

`mkBundle` is a build helper that aims to facilitate the creation of system
specific bundles. It is intended to be the base bundle, which will prepare you
application to be bundled again for a specific format.

In essence, `mkBundle` iterates over the derivation closure, patches all
references to it and organizes its dependencies, so you can just move then
around without fear of break anything.

- `mkBundle` assembles its payload through `lib.deployTools.mkCompactClosure`,
  which prunes the bundle closure using a small set of filters. By default these
  filters drop paths whose basename matches `-bash-`, `-coreutils-`, or
  `-less-`, keeping bundles lean without sacrificing typical runtime
  requirements. Extend or trim the lists via the `referenceExcludes`
  attrset—`useDefaults` defaults to `true`, `extraPatterns` combines with the
  basename matcher, and `extraPaths` accepts concrete store paths when you need
  to exclude specific artifacts.

  ```nix
  referenceExcludes = {
    extraPatterns = [ "-foo-" ];
    extraPaths = [ "/nix/store/..." ];
    useDefaults = true;
  };
  ```

  You can also call the helper directly:

  ```nix
  compactClosure = deployTools.mkCompactClosure { extraPatterns = [ "-foo-" ]; };
  ```

  Set `useDefaults = false` when you need a pristine closure.
  - Advanced users may replace the helper entirely by overriding the
    `compactClosure` attribute; `mkBundle` will respect the provided derivation
    and skip its internal helper wiring.
- Libraries goes to `libPath` relative to the derivation! If `style` is
  `self-contained`, you really don't need to touch here. If `style` is
  `system-trust`, you are expected to guarantee that the libs inside `libPath`
  will be at `/usr/lib64`
- The interpreter is always set to `/lib64/ld-linux-x86-64.so.2`, which is the
  default for `x86_64-linux`.
- Self references will be rebased to `${installPrefix}`. Ex.:
  `/nix/store/...-hello-relocated-2.12.3/share` will be
  `${installPrefix}/share`.
- Other references will be merged into `${installPrefix}`. Ex.:
  `/nix/store/...-other/share` will be `${installPrefix}/share`.

## Handy Tools

- `patchelf`: used to patch interpreter and `rpath`
- `patchstrings`: used to patch strings inside binaries (length of the new
  string should be lower or equal to the old string)
- `copyclosure`: used to make a copy of the closure
