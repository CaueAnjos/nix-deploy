# Nix-Deploy

<!--toc:start-->

- [Nix-Deploy](#nix-deploy)
  - [What Is This?](#what-is-this)
  - [What Can It Be Used For?](#what-can-it-be-used-for)
  - [Installation](#installation)
  - [How It Works](#how-it-works)
    - [The Pipeline](#the-pipeline)
    - [The `mkBundle` Contract](#the-mkbundle-contract)
    - [Handy Tools](#handy-tools)
  - [Limitations](#limitations)

<!--toc:end-->

> An easy way to prepare your Nix-built software for packaging and deploy it as
> RPM, DEB, AppImage, Windows installers, and more.

## What Is This?

**Nix-Deploy** is a Nix flake that exposes a library, `deployTools`, plus two
standalone command-line packages, `patchelf` and `patchstrings`.

Its job is narrow and specific: take the Nix store closure of a derivation and
turn it into a relocatable, self-contained directory tree whose internal
`/nix/store/...` references have been rewritten to point at a different install
path (for example `/opt/myapp`), so the payload behaves correctly once copied
there — without a Nix store present at runtime.

**Nix-Deploy does not itself produce RPMs, DEBs, AppImages, or Windows
installers.** It produces the relocated payload directory; wrapping that payload
into one of those formats is left to whatever packaging tool you normally use
for that target.

## What Can It Be Used For?

The main use case is preparing Nix-built software for distribution on systems
that don't have Nix or NixOS: you build your package with Nix as usual, then use
`deployTools.mkBundle` to produce a directory tree rooted at your chosen install
prefix, with every ELF interpreter/rpath and every embedded store-path string
patched to match. That directory tree is what you hand off to `rpmbuild`,
`dpkg-deb`, `appimagetool`, an installer builder, a container `COPY` step, or
any other traditional packaging pipeline.

The repository ships a few example/test packages built against `pkgs.hello` that
illustrate the pieces involved (see `packages/default.nix`):

- `test-compact` — `deployTools.mkCompactClosure pkgs.hello`, the deduplicated
  closure of `pkgs.hello` symlinked together into a single derivation.
- `test-bundle` — `deployTools.mkBundle { drv = pkgs.hello; }`, the full
  relocated bundle built from that closure.
- `test-closure` — `deployTools.mkClosure pkgs.hello`, the full closure of
  `pkgs.hello` copied (not symlinked) into `$out/nix/store`.

> [!TIP]
> `nix build .#test-bundle` is a good smoke test after cloning the repo: it
> exercises the whole pipeline (closure collection, compaction, and patching)
> end to end against a small, well-known package.

## Installation

Add this flake as an input and apply its `overlays.default` overlay to your
`nixpkgs` import, the same way `flake.nix` does for its own `perSystem`
(`overlays = with self.overlays; [ default ];`). The overlay adds a
`deployTools` attribute set to `pkgs`, plus `pkgs.patchstrings` (`pkgs.patchelf`
already comes from nixpkgs itself; this flake re-exposes it under
`packages.patchelf` for convenience, it doesn't need to be overlaid).

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/26.05";
    nix-deploy.url = "github:CaueAnjos/nix-deploy";
  };

  outputs = {
    self,
    nixpkgs,
    nix-deploy,
    ...
  }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      overlays = [nix-deploy.overlays.default];
    };
  in {
    packages.${system}.myapp-bundle = pkgs.deployTools.mkBundle {
      drv = pkgs.myapp;
      installPrefix = "/opt/myapp";
    };
  };
}
```

Once the overlay is applied, `pkgs.deployTools` exposes:

- `deployTools.mkBundle` — the main bundling helper (see below).
- `deployTools.mkReferences` — collects a derivation's closure; `mode = "full"`
  uses `referencesByPopularity` for a popularity-sorted full closure,
  `mode = "runtime"` (the default) computes only the actual runtime-reachable
  subset via BFS through transitive dependencies, and `mode = "minimal"`
  combines embedded-string scanning and ELF rpath/needed walking for a combined
  scope. Takes `{ drv, reverse ? false, mode ? "runtime", output ? "nix" }`;
  `reverse = true` reverses the line order. `output` changes the output style.
  It can be `file` or `nix`.
- `deployTools.mkCompactClosure` — dedupes a derivation's closure into a flat,
  symlinked directory.
- `deployTools.mkClosure` — copies (rather than symlinks) a derivation's full
  closure into `$out/nix/store`.
- `deployTools.mkCopyclosureCommand` — builds a `copyclosure` script scoped to
  one derivation's references.

> [!NOTE]
> `pkgs.patchstrings` is reliably available through the overlay because it's
> defined directly in `packages/default.nix`. Do not rely on `pkgs.copyclosure`
> or `pkgs.runtimedeps` being exposed the same way — see
> [Limitations](#limitations).

## How It Works

### The Pipeline

`mkBundle` is built on top of three smaller pieces, all part of `deployTools`:

1. **`deployTools.mkReferences { drv }`** collects the derivation's closure
   using `mode = "runtime"` by default (transitive BFS over actual
   runtime-reachable paths), or `mode = "full"` for the popularity-sorted full
   closure via `referencesByPopularity`, or `mode = "minimal"` for combined
   embedded-string and ELF rpath/needed scanning, producing a text file listing
   store paths.
2. **`deployTools.mkCompactClosure drv`** reads that file, drops empty lines,
   deduplicates the remaining paths, keeps only the ones that are directories in
   the store (`lib.pathIsDirectory`), and joins them together into one
   derivation with `symlinkJoin`. The result is a single directory whose top
   level is a flat union of every store path in the closure.
3. **`deployTools.mkBundle`** copies that compact closure into its build
   directory (`rsync -a -L`, so symlinks are dereferenced into real files), then
   walks every file in parallel and patches it in place.

### The `mkBundle` Contract

```nix
pkgs.deployTools.mkBundle {
  drv = your-derivation;
  installPrefix = "/opt/${your-derivation.pname}";
}
```

Relevant arguments (see `lib/deployTools/mkBundle.nix`):

| Argument         | Default                                                                          | Meaning                                                                  |
| ---------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------ |
| `drv`            | _(required)_                                                                     | The derivation to bundle. Must have `pname`/`version` unless overridden. |
| `pname`          | `"${drv.pname}-bundled"`                                                         | Name of the resulting bundle derivation.                                 |
| `version`        | `drv.version`                                                                    | Version of the resulting bundle derivation.                              |
| `installPrefix`  | `"/opt/${drv.pname}"`                                                            | Path the bundle will be installed to at deploy time.                     |
| `interpreter`    | `${installPrefix}/lib64/ld-linux-x86-64.so.2` (or `lib/ld-linux.so.2` on 32-bit) | ELF interpreter path stamped into patched binaries.                      |
| `rpath`          | `/lib`                                                                           | Fixed rpath used only when `absolute = true`.                            |
| `absolute`       | `false`                                                                          | See below.                                                               |
| `compactClosure` | `deployTools.mkCompactClosure drv`                                               | Overridable; lets you swap the closure-building step entirely.           |
| `patchScript`    | `./mkBundle/patch.sh`                                                            | The per-file patch script run against every file in the closure.         |

By default (`absolute = false`), `mkBundle` computes **`$ORIGIN`-relative**
rpaths: for every existing rpath entry that points into `/nix/store`, it derives
the equivalent relative path from the binary's location to that entry's subpath
under `installPrefix`, and rewrites the rpath entry as `$ORIGIN/...`. Set
`absolute = true` (and provide `rpath`) to instead stamp a single, fixed
absolute rpath on every patched ELF file. The interpreter is always rewritten to
an absolute path (`interpreter`) regardless of mode.

Every embedded `/nix/store/<hash>-<name>...` string reference (in both ELF
binaries and plain text files such as scripts or config files) is rewritten to
`installPrefix`.

> [!IMPORTANT]
> References remain **absolute** paths after patching (rooted at
> `installPrefix`, or `$ORIGIN`-relative rpaths pointing back into the same
> tree) — nothing is made relative to a movable "current directory". This is
> intentional, for reproducibility: the bundle is meant to be extracted to
> exactly one place, `installPrefix`.

`mkBundle` is a regular `stdenv.mkDerivation` call under the hood, so
`buildPhase`, `installPhase`, `configurePhase`, `unpackPhase`, and any other
derivation attribute can be overridden by simply passing them as extra
arguments. Only `drv` and `compactClosure` are stripped out before being
forwarded to `stdenv.mkDerivation` (see `privateArgNames` in
`lib/deployTools/mkBundle.nix`); every other attribute you pass — including ones
not listed above — passes straight through.

Advanced users can replace closure-building entirely by overriding
`compactClosure` with their own derivation; `mkBundle` doesn't care how it was
produced, only that it contains the files to be patched.

### Handy Tools

- **`patchelf`** — used to patch the ELF interpreter and rpath of executables
  and shared libraries. This is nixpkgs' own `patchelf`, re-exposed as a flake
  package/overlay entry for convenience.
- **`patchstrings`** — a small Perl tool (`src/patchstrings`) used to find and
  rewrite strings embedded in files. It supports:
  - `patchstrings --find <regex> <path>` — list matches without patching.
  - `patchstrings <old> <new> <file>` — literal replacement.
  - `patchstrings --regex 's|PATTERN|REPLACEMENT|flags' <file>` — regex-based
    substitution (this is the mode `mkBundle` uses).
  - `--text` — allow the file to grow or shrink (safe for plain text files).
  - Binary mode (the default, i.e. without `--text`) requires the replacement
    string to be **equal to or shorter than** the original; any gap left by a
    shorter replacement must be filled. For padding/filling, binary mode
    supports:
    - `--pad-str <char>` — fills the gap at the END of the entire enclosing
      printable-ASCII run (default `\x00`, i.e. NUL bytes). The character
      argument must be exactly 1 character.
    - `--fill-str <char>` — fills the gap immediately AFTER each match, before
      any unchanged suffix that follows it, locally within the run (rather than
      at the tail). The character argument must be exactly 1 character.
    - `--pad-str` and `--fill-str` are mutually exclusive.
    - If a binary-mode replacement would be _longer_ than the original,
      `patchstrings` refuses and exits with an error instead of corrupting the
      file.
- **`copyclosure`** (via `deployTools.mkCopyclosureCommand`) — generates a
  script that copies (rather than symlinks) every path in a derivation's closure
  into a target directory.

> [!WARNING]
> NUL-padding a shortened binary string is fine for plain, NUL-terminated C
> strings, but it can corrupt values for runtimes that store an _explicit_
> string length instead of relying on NUL-termination (for example Perl SVs or
> Ruby RStrings). Those readers happily read past the shortened content and pick
> up the raw `\0` bytes as part of the string. When patching path-like strings,
> use `--fill-str '/'` instead — the extra path separators are semantically a
> no-op for directory-style paths, and filling locally (rather than at the tail)
> matters when a single string run contains multiple concatenated store-path
> references. This is exactly what `mkBundle`'s `patch.sh` does for its own
> binary-mode string patching pass (`patchstrings --fill-str '/' --regex ...`),
> and this choice should not be regressed to `--pad-str` or default padding.

## Limitations

- **Linux only.** `mkBundle` emits a `lib.warnIfNot stdenv.isLinux` warning (it
  does not hard-fail) if built on a non-Linux `stdenv`, but the ELF patching
  logic (`readelf`, `patchelf --set-rpath`/`--set-interpreter`) is meaningless
  outside Linux.
- **Binary string patching is length-constrained.** Outside of `--text` mode, a
  replacement string can never be longer than the string it replaces;
  `patchstrings` refuses to patch and errors out rather than growing a binary
  file in place. This is why `installPrefix` needs to be no longer than the
  `/nix/store/<hash>-<name>` prefixes it replaces, or `mkBundle`'s patch pass
  will fail on some files.
- **The NUL-padding caveat is real and easy to regress.** Default padding
  (`\x00`) is only safe for plain, NUL-terminated strings. Anything that tracks
  its own length (Perl SVs, Ruby RStrings, etc.) needs `--fill-str '/'` or
  equivalent — see the warning above.
- **`mkCompactClosure` filters on "is this a directory", nothing more.** It
  keeps only closure entries that are directories in the Nix store and drops
  everything else (empty lines, non-directory paths); it has no mechanism for
  excluding specific packages or subpaths from the bundle. If you need to
  exclude something from a bundle's closure, you currently have to override
  `compactClosure` on `mkBundle` yourself rather than configure the built-in
  helper.
- **This project stops at the relocated closure.** It does not generate `.rpm`,
  `.deb`, `.AppImage`, `.msi`, or any other package format itself — those steps
  are expected to consume the directory tree `mkBundle` produces.

> [!TIP]
> `nix develop` gives you a shell with `patchelf` and `patchstrings` on `PATH`
> for experimenting with either tool directly against a file.
