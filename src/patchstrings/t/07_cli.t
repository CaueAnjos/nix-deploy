use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 18;
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
# --pad-str dispatch (binary mode, path-safe fill)
# ---------------------------------------------------------------------------

{
    my $path = "/nix/store/abcdefghijklmnopqrstuvwxyz0123456-perl-5.36.0";
    my $data = "\x01\x02" . $path . "\x00" x 10 . "\x03\x04";
    my $f    = tmp_with($data);

    capture { run(['--pad-str', '/', $path, '/opt/myapp', $f]) };

    my $result = read_file($f);
    is(length($result), length($data), 'CLI --pad-str: file size unchanged');
    like($result, qr{/opt/myapp/+}, 'CLI --pad-str: path patched and slash-padded');
}

# ---------------------------------------------------------------------------
# --pad-str without argument dies
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    eval { run(['--pad-str']) };
    like($@, qr/\[error\]/, '--pad-str without argument: dies');
}

# ---------------------------------------------------------------------------
# --fill-str dispatch (binary mode, local fill)
# ---------------------------------------------------------------------------

{
    my $path = "/nix/store/abcdefghijklmnopqrstuvwxyz0123456-hello";
    my $data = "\x01\x02" . $path . "/bin/hello" . "\x00" x 10 . "\x03\x04";
    my $f    = tmp_with($data);

    capture { run(['--fill-str', '/', $path, '/opt/hello', $f]) };

    my $result = read_file($f);
    is(length($result), length($data), 'CLI --fill-str: file size unchanged');
    like($result, qr{/opt/hello/+bin/hello},
        'CLI --fill-str: fill lands between replacement and suffix, not at tail');
}

# ---------------------------------------------------------------------------
# --fill-str without argument dies
# ---------------------------------------------------------------------------

{
    eval { run(['--fill-str']) };
    like($@, qr/\[error\]/, '--fill-str without argument: dies');
}

# ---------------------------------------------------------------------------
# --pad-str / --fill-str longer than one character dies
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    eval { run(['--pad-str', '//', 'a', 'b', $f]) };
    like($@, qr/\[error\].*one character/, '--pad-str longer than one character: dies');
}

{
    my $f = tmp_with("hello world");
    eval { run(['--fill-str', '//', 'a', 'b', $f]) };
    like($@, qr/\[error\].*one character/, '--fill-str longer than one character: dies');
}

# ---------------------------------------------------------------------------
# --pad-str and --fill-str together dies
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    eval { run(['--pad-str', '/', '--fill-str', '/', 'a', 'b', $f]) };
    like($@, qr/\[error\].*mutually exclusive/,
        '--pad-str and --fill-str together: dies');
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
