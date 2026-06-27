{
  writeShellApplication,
  perl,
}:
writeShellApplication {
  name = "patchstrings";
  runtimeInputs = [perl];
  text = ''
    perl -I ${../src/patchstrings/lib} ${../src/patchstrings/bin/patcher.pl} "$@"
  '';
}
