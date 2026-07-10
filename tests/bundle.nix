{
  perSystem = {
    pkgs,
    lib,
    ...
  }: {
    checks = let
      mkTestPackage = drv: {
        test-bundle = pkgs.deployTools.mkBundle {
          inherit drv;
          installPrefix = "/app";
        };
        installPrefix = "/app";
        mainBinary = builtins.elemAt (builtins.match "^/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+/(.+)" (lib.getExe drv)) 0;
      };

      mkBundleTest = {
        installPrefix,
        mainBinary,
        test-bundle,
      }: {
        "bundle-static-checks_${test-bundle.pname or test-bundle.name}" =
          pkgs.runCommand "bundle-static-checks"
          {}
          ''
            set -euo pipefail
            bundle=${test-bundle}
            fail() { echo "FAIL: $1" >&2; exit 1; }

            echo "== checking ELF binaries under $bundle =="

            while read -r f; do
              interp="$(patchelf --print-interpreter "$f" 2>/dev/null || true)"
              rpath="$(patchelf --print-rpath "$f" 2>/dev/null || true)"

              if [[ -z $interp && -z $rpath ]]; then
                  continue
              fi

              echo "-- $f"
              echo "   interpreter: $interp"
              echo "   rpath:       $rpath"

              NIX_STRING_REGEX="/nix/store/[0-9a-df-np-sv-z]{32}-[A-Za-z0-9+._?=-]+"
              validation_regex="^$NIX_STRING_REGEX"

              if [[ $interp && $interp =~ $validation_regex ]]; then
                fail "$f has interpreter on the nix store: $interp"
              fi

              if [[ $rpath ]]; then
                IFS=':' read -ra parts <<< "$rpath"
                for p in "''${parts[@]}"; do
                  [[ -z "$p" ]] && continue

                  if [[ $p =~ $validation_regex ]]; then
                    fail "$f has rpath entry on nix store: $p"
                  fi
                done
              fi
            done < <(find "$bundle" -type f)

            echo "== scanning for stray /nix/store references =="

            set +e
            left_references=$(patchstrings --find "$NIX_STRING_REGEX" "$bundle" 2>/dev/null | wc -l)
            set -e

            if [[ "$left_references" -eq 0 ]]; then
                echo "Clean: no nix store references remaining."
            else
                fail "$left_references nix store reference(s) still present"
            fi

            touch $out
          '';

        "bundle-vm-runs_${test-bundle.pname or test-bundle.name}" = pkgs.testers.runNixOSTest {
          name = "bundle-vm-runs";

          nodes.machine = _: {
            virtualisation.diskSize = 8192;
          };

          testScript =
            /*
            python
            */
            ''
              machine.start()
              machine.wait_for_unit("multi-user.target")

              machine.succeed("mkdir -p ${installPrefix}")
              machine.succeed("cp -r '${test-bundle}/.' '${installPrefix}'")

              status, output = machine.execute("timeout 5 ${installPrefix}/${mainBinary} >/dev/null 2>&1")

              if status == 126:
                  raise Exception("Not executable")
              elif status == 127:
                  raise Exception("Not found")
            '';
        };
      };

      test-packages = with pkgs; [
        (mkTestPackage hello)
        (mkTestPackage ffmpeg)
        (mkTestPackage cowsay)
        (mkTestPackage yazi)
      ];
    in
      lib.attrsets.mergeAttrsList (lib.forEach test-packages mkBundleTest);
  };
}
