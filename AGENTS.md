# Nix-Deploy Agent Notes

## Quick Start
- Use `nix develop` for a shell with `patchelf`/`patchstrings`; the flake assumes Linux targets (`mkBundle` warns otherwise).
- Fast smoke test: `nix build .#test-bundle` builds the sample hello bundle and exercises the closure tooling.

## deployTools Layout
- `lib/default.nix` now exports a recursive `deployTools` attrset; when adding helpers, add them inside the `rec` block so existing calls (e.g. `mkBundle` -> `deployTools.mkCompactClosure`) resolve correctly.
- `lib/deployTools/references.nix` is a thin wrapper around `referencesByPopularity`; everything consuming closure info should call `deployTools.references drv`.
- `lib/deployTools/mkCompactClosure.nix` takes a single positional `drv` arg, reads that references file into a deduped list, filters to keep only entries that are directories in the store (`lib.pathIsDirectory (builtins.storePath path)`), and returns a `symlinkJoin` of them. The directory-filter is the only filtering step present; path exclusion/inclusion logic belongs in `references.nix`, not here or in `mkBundle`.

## mkBundle Contract
- `mkBundle` now depends on `deployTools.mkCompactClosure`; `compactClosure` defaults to `deployTools.mkCompactClosure drv` (a plain positional call, no attrset).
- The `compactClosure` argument is overridable for advanced use; remove it from the attrset forwarded to `stdenv.mkDerivation`. `privateArgNames` is `["drv" "compactClosure"]`; if you add more private knobs, remember to extend it.

## Packages & Apps
- `packages/default.nix` exposes convenience bundles (`test-bundle`, `test-compact`, `hello-closure`) and `patchstrings` (plus re-exposes `patchelf` from nixpkgs). The `overlayAttrs` tries to also inherit `copyclosure` and `runtimedeps`, but these are not defined in `config.packages` — this is a latent bug (the overlay will fail if those attributes are ever accessed). Update this when adding new deploy tooling so overlays stay in sync.
- Scripts live under `scripts/`; `nix run .#hello` invokes the demo app via the flake `apps` entry.

## Gotchas
- The closure helper reads a plain-text path list; avoid generating non-store paths. If you need to tweak ordering, adjust at the source (references generator) rather than post-processing.
- Because `mkBundle` copies the `compactClosure` output during `configurePhase`, any mutation you do afterward (e.g. patching files) must happen under `final/`.
- `lib/deployTools/mkBundle/patch.sh`'s binary-mode `patch_strings()` pass must keep passing `--pad-str '/'` to `patchstrings`; the default NUL padding corrupts store-path references for interpreted languages that track explicit string lengths (Perl SVs, Ruby RStrings, etc.). Don't let this regress back to default padding.
