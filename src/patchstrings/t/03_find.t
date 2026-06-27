use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 10;
use File::Temp qw(tempfile tempdir);
use Capture::Tiny qw(capture_stdout);

use Patcher::Find qw(find_strings locate_printable_strings run_find);

# ---------------------------------------------------------------------------
# find_strings
# ---------------------------------------------------------------------------

# Basic match
{
    my $data = "hello world\x00garbage\x00foo bar";
    my @m = find_strings($data, qr/\w+/);
    ok(scalar @m > 0, 'find_strings returns matches');
}

# No match
{
    my $data = "hello world";
    my @m = find_strings($data, qr/ZZZNOMATCH/);
    is(scalar @m, 0, 'find_strings returns empty list on no match');
}

# Deduplication
{
    my $data = "repeat repeat repeat";
    my @m = find_strings($data, qr/repeat/);
    is(scalar @m, 1, 'find_strings deduplicates matches');
}

# Short runs (< 4 chars) are ignored
{
    my $data = "\x00hi\x00";
    my @m = find_strings($data, qr/hi/);
    is(scalar @m, 0, 'find_strings ignores runs shorter than 4 chars');
}

# ---------------------------------------------------------------------------
# locate_printable_strings
# ---------------------------------------------------------------------------

{
    my $data = "abcdef\x00ghijkl";
    my @runs = locate_printable_strings($data);
    is(scalar @runs, 2, 'locate_printable_strings finds two runs');
    is($runs[0]{offset}, 0,      'first run starts at offset 0');
    is($runs[0]{text},   'abcdef', 'first run text is correct');
    is($runs[1]{offset}, 7,      'second run starts after NUL');
    is($runs[1]{text},   'ghijkl', 'second run text is correct');
}

# ---------------------------------------------------------------------------
# run_find — integration: stdout output
# ---------------------------------------------------------------------------
{
    my ($fh, $fname) = tempfile(UNLINK => 1);
    print $fh "https://api.oldserver.com/v2/users\x00other stuff here";
    close $fh;

    my $stdout = capture_stdout { run_find('oldserver', $fname) };
    like($stdout, qr/oldserver/, 'run_find prints matching strings to stdout');
}
