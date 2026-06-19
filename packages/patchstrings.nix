{
  writeShellApplication,
  perl,
}:
writeShellApplication {
  name = "patchstrings";
  runtimeInputs = [perl];
  text = builtins.readFile ../src/patchstrings/patchstrings.sh;
}
