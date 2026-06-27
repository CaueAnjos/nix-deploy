package Patcher::File;

use strict;
use warnings;
use Exporter 'import';
use Patcher::Util qw(die_err);

our @EXPORT_OK = qw(read_file write_file validate_target);

# Validate that a path exists, is a regular file, and is readable+writable.
sub validate_target {
    my ($path, $func) = @_;
    -e $path or die_err("'$path' does not exist");
    -f $path or die_err("'$path' is not a regular file");

    if ( $func eq "r") {
     -r $path or die_err("'$path' is not readable");
    }

    if ( $func eq "w") {
     -w $path or die_err("'$path' is not writable");
    }

    return 1;
}

# Slurp a file in raw (binary-safe) mode.
sub read_file {
    my ($path) = @_;
    validate_target($path, "r");
    open(my $fh, '<:raw', $path) or die_err("cannot open '$path' for reading: $!");
    my $data = do { local $/; <$fh> };
    close $fh;
    return $data;
}

# Write data to a file in raw (binary-safe) mode.
sub write_file {
    my ($path, $data) = @_;
    validate_target($path, "w");
    open(my $fh, '>:raw', $path) or die_err("cannot open '$path' for writing: $!");
    print $fh $data;
    close $fh;
}

1;
