{
  rsync,
  runCommand,
  symlinkJoin,
  jdupes,
}: {
  name,
  paths,
  deduplicate ? "symlink",
}: let
  symlink = symlinkJoin {inherit name paths;};

  join =
    runCommand name {nativeBuildInputs = [rsync jdupes];}
    ''
      mkdir -p "$out"
      rsync -a -L "${symlink}/." "$out" || {
        status=$?
        if [ "$status" -ne 23 ]; then
          exit "$status"
        fi
      }

      chmod -R u+w "$out"

      ${
        if deduplicate == null
        then ""
        else
          /*
          bash
          */
          ''
            jdupes -r ${
              if deduplicate == "symlink"
              then "-l"
              else if deduplicate == "hardlink"
              then "-L"
              else throw "unkown `${deduplicate}` deduplicate. Use: symlink, hardlink or null to skip deduplication step."
            } "$out"
          ''
      }
    '';
in
  join
