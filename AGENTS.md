# Nix-Deploy Agent Notes

## Quick Start
- Use `nix develop` for a shell with `patchelf`/`patchstrings`; the flake assumes Linux targets (`mkBundle` warns otherwise).
- Fast smoke test: `nix build .#test-bundle` builds the sample hello bundle and exercises the closure tooling.

## deployTools Layout
- `lib/default.nix` exports a flat `deployTools` function that accepts `{pkgs, ...}` and returns an attrset of helpers.
- `lib/deployTools/mkReferences.nix` wraps closure scanners in three modes. Takes `{ drv, reverse ? false, mode ? "runtime" }` (default `mode` is `"runtime"`); `mode = "full"` uses `referencesByPopularity` for a popularity-sorted full closure, `mode = "runtime"` delegates to BFS-based transitive dependency filtering via `src/references/runtimedeps.sh` (fixed: old version only checked root drv's direct refs, now fully transitive), `mode = "minimal"` uses a combined embedded-string scanner and ELF rpath/needed walker (`src/references/minimaldeps.sh`) to collect both hardcoded paths and dynamic library dependencies. `reverse = true` reverses output line order.
- `lib/deployTools/mkCompactClosure.nix` takes a single positional `drv` arg, calls `deployTools.mkReferences { inherit drv; }` to get the full closure, dedupes it, filters to keep only directories in the store (`lib.pathIsDirectory`), and returns a `symlinkJoin`. The directory-filter is the only filtering step; path exclusion/inclusion logic belongs in `mkReferences`, not here or in `mkBundle`.

## mkBundle Contract
- `mkBundle` now depends on `deployTools.mkCompactClosure`; `compactClosure` defaults to `deployTools.mkCompactClosure drv` (a plain positional call, no attrset).
- The `compactClosure` argument is overridable for advanced use; remove it from the attrset forwarded to `stdenv.mkDerivation`. `privateArgNames` is `["drv" "compactClosure"]`; if you add more private knobs, remember to extend it.
- `mkCompactClosure` internally calls `deployTools.mkReferences { inherit drv; }` (attrset call with default `mode = "runtime"`).

## Packages & Apps
- `packages/default.nix` exposes convenience bundles (`test-bundle`, `test-compact`, `hello-closure`) and `patchstrings` (plus re-exposes `patchelf` from nixpkgs). The `overlayAttrs` tries to also inherit `copyclosure` and `runtimedeps`, but these are not defined in `config.packages` — this is a latent bug (the overlay will fail if those attributes are ever accessed). Update this when adding new deploy tooling so overlays stay in sync.
- `packages/patchstrings.nix` is a `perlPackages.buildPerlPackage` derivation (not `writeShellApplication`) built from `src/patchstrings/Makefile.PL`, with test-only `Capture::Tiny` in `buildInputs`. The full Perl test suite (`t/*.t` files) runs automatically during the Nix build's checkPhase. The distribution's `Makefile.PL` has `NAME => 'Patcher'`, `VERSION => '0.1.0'`, `LICENSE => 'gpl_3'`, and `EXE_FILES => ['bin/patchstrings']` (the installed binary is `patchstrings`, renamed from the old `patcher.pl`).
- Scripts live under `scripts/`; `nix run .#hello` invokes the demo app via the flake `apps` entry.

## Gotchas
- The closure helper reads a plain-text path list; avoid generating non-store paths. If you need to tweak ordering, adjust at the source (references generator) rather than post-processing.
- Because `mkBundle` copies the `compactClosure` output during `configurePhase`, any mutation you do afterward (e.g. patching files) must happen under `final/`.
- In bash helper functions, unscoped `for var in ...` loop variables can silently clobber a `local` variable of the same name in any caller up the call stack (bash's `local` is scoped per function *call*, not per function definition). Always scope loop variables — rename them or declare `local` explicitly to avoid collisions. This caused an unbounded recursion bug in `src/references/minimaldeps.sh` until the loop variable in `is_seen_path()` was renamed from `item` to `seen_item`; the corruption made `library_references()` keep re-`find`-ing the root derivation path, which segfaulted real `nix build` runs (bash stack overflow) instead of terminating.
- `src/references/minimaldeps.sh`'s `library_references` pass resets its "seen" set right before the walk starts; don't pre-seed that reset with `$DRV` itself (`seen_paths=("$DRV")`) — `$DRV` is also the first path fed into the walk, so pre-seeding it makes the very first call return immediately as "already seen" and skips scanning `$DRV`'s own directory tree (e.g. its `bin/` output) with `patchelf` entirely. Reset with `seen_paths=()` instead; `$DRV` gets added to the seen set naturally once it's actually processed.
- `lib/deployTools/mkBundle/patch.sh`'s binary-mode `patch_strings()` pass now passes `--fill-str '/'` to `patchstrings` (not `--pad-str`). This matters because `NIX_STORE_REGEX` matches one-or-more concatenated store paths with no separator: `--fill-str` closes each match's gap locally after its own replacement, preserving boundaries with whatever follows, whereas `--pad-str` would accumulate all slack at the tail. The default NUL padding corrupts store-path references for interpreted languages that track explicit string lengths (Perl SVs, Ruby RStrings, etc.). Don't regress this to `--pad-str` or default padding.
