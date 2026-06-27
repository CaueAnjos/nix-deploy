use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 6;
use File::Temp qw(tempfile);

use Patcher::File qw(read_file write_file validate_target);

# --- write then read round-trip -------------------------------------------
my ($fh, $fname) = tempfile(UNLINK => 1);
close $fh;

write_file($fname, "hello\x00world");
my $data = read_file($fname);
is($data, "hello\x00world", 'round-trip preserves binary content');

# --- validate_target: non-existent file ------------------------------------
eval { validate_target('/no/such/file/abc123') };
like($@, qr/\[error\].*does not exist/, 'validate_target dies on missing file');

# --- validate_target: directory --------------------------------------------
eval { validate_target('/tmp') };
like($@, qr/\[error\].*not a regular file/, 'validate_target dies on directory');

# --- validate_target: not readable -----------------------------------------
SKIP: {
    skip "cannot test permissions as root", 1 if $> == 0;
    my ($fh2, $fname2) = tempfile(UNLINK => 1);
    close $fh2;
    chmod 0000, $fname2;
    eval { validate_target($fname2) };
    like($@, qr/\[error\].*not readable/, 'validate_target dies on unreadable file');
    chmod 0644, $fname2;
}

# --- validate_target: not writable -----------------------------------------
SKIP: {
    skip "cannot test permissions as root", 1 if $> == 0;
    my ($fh3, $fname3) = tempfile(UNLINK => 1);
    close $fh3;
    chmod 0444, $fname3;
    eval { validate_target($fname3) };
    like($@, qr/\[error\].*not writable/, 'validate_target dies on read-only file');
    chmod 0644, $fname3;
}

# --- read_file on a non-existent path dies --------------------------------
eval { read_file('/no/such/path/xyz') };
like($@, qr/\[error\]/, 'read_file dies on missing path');
