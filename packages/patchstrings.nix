{
  perlPackages,
  lib,
}:
perlPackages.buildPerlPackage {
  pname = "patchstrings";
  version = "0.1.0";
  src = ../src/patchstrings;

  # No POD/man pages are generated (Makefile.PL doesn't produce any), so
  # there's nothing to split into a separate "devdoc" output.
  outputs = ["out"];

  # Capture::Tiny is a test-only dependency (t/06_patch.t, t/07_cli.t);
  # everything else the test suite/CLI needs (Test::More, FindBin,
  # File::Temp, Getopt::Long, Exporter) is core Perl.
  buildInputs = [perlPackages.CaptureTiny];

  meta = {
    description = "Patch embedded strings and ELF metadata for Nix store relocation";
    license = lib.licenses.gpl3Only;
    mainProgram = "patchstrings";
  };
}
