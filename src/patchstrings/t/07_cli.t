use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 9;
use File::Temp qw(tempfile);
use Capture::Tiny qw(capture);

use Patcher::CLI  qw(run);
use Patcher::File qw(read_file write_file);

sub tmp_with {
    my ($content) = @_;
    my ($fh, $fname) = tempfile(UNLINK => 1);
    binmode $fh, ':raw';
    print $fh $content;
    close $fh;
    return $fname;
}

# ---------------------------------------------------------------------------
# --find dispatch
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("https://api.oldserver.com/v2/users\x00other stuff here");
    my $stdout = capture { run(['--find', 'oldserver', $f]) };
    like($stdout, qr/oldserver/, '--find dispatches and prints results');
}

# ---------------------------------------------------------------------------
# Literal patch dispatch
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    capture { run(['--text', 'world', 'earth', $f]) };
    is(read_file($f), "hello earth", 'CLI literal patch with --text');
}

# ---------------------------------------------------------------------------
# Regex patch dispatch
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("foo 123 bar");
    capture { run(['--text', '--regex', 's/\d+/NUM/', $f]) };
    is(read_file($f), "foo NUM bar", 'CLI regex patch with --regex --text');
}

# ---------------------------------------------------------------------------
# --dry-run prevents write
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    capture { run(['--text', '--dry-run', 'world', 'earth', $f]) };
    is(read_file($f), "hello world", '--dry-run leaves file unchanged');
}

# ---------------------------------------------------------------------------
# --verbose produces extra output
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    my ($out) = capture { run(['--text', '--verbose', 'world', 'earth', $f]) };
    like($out, qr/\[patch\]/, '--verbose prints patch details');
}

# ---------------------------------------------------------------------------
# Missing arguments
# ---------------------------------------------------------------------------

{
    eval { run([]) };
    like($@, qr/\[error\].*usage/, 'no args: dies with usage message');
}

{
    eval { run(['--find']) };
    like($@, qr/\[error\]/, '--find without args: dies with error');
}

{
    eval { run(['--regex']) };
    like($@, qr/\[error\]/, '--regex without expression: dies');
}

{
    eval { run(['--regex', 's/a/b/']) };
    like($@, qr/\[error\].*<file>/, '--regex without file: dies');
}
