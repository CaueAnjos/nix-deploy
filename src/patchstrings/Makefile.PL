use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME      => 'Patcher',
    ABSTRACT  => 'Patch embedded strings and ELF metadata for Nix store relocation',
    VERSION   => '0.1.0',
    LICENSE   => 'gpl_3',
    EXE_FILES => ['bin/patchstrings'],
    PREREQ_PM => {
        'Getopt::Long' => 0,
        'Exporter'     => 0,
        'FindBin'      => 0,
        'File::Temp'   => 0,
    },
    TEST_REQUIRES => {
        'Test::More'    => 0,
        'Capture::Tiny' => 0,
    },
);
