{
  writeShellApplication,
  perl,
}:
writeShellApplication {
  name = "patchstrings";
  runtimeInputs = [perl];
  text = ''
    perl ${../src/patchstrings/patchstrings.pl} "$@"
  '';
}
