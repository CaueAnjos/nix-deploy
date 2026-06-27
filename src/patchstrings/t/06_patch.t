use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 19;
use File::Temp qw(tempfile);
use Capture::Tiny qw(capture);

use Patcher::Patch qw(patch_literal patch_regex);
use Patcher::File  qw(read_file write_file);

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

sub tmp_with {
    my ($content) = @_;
    my ($fh, $fname) = tempfile(UNLINK => 1);
    binmode $fh, ':raw';
    print $fh $content;
    close $fh;
    return $fname;
}

# ---------------------------------------------------------------------------
# patch_literal — text mode
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    my ($out) = capture { patch_literal($f, "world", "earth", text_mode => 1) };
    is(read_file($f), "hello earth", 'literal text: replacement applied');
    like($out, qr/1 occurrence/, 'literal text: output mentions 1 occurrence');
}

# ---------------------------------------------------------------------------
# patch_literal — multiple occurrences in text mode
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("cat cat cat");
    capture { patch_literal($f, "cat", "dog", text_mode => 1) };
    is(read_file($f), "dog dog dog", 'literal text: all occurrences replaced');
}

# ---------------------------------------------------------------------------
# patch_literal — binary mode (NUL padding at string tail)
# ---------------------------------------------------------------------------

{
    # Build a binary: two bytes + the URL + NUL pad + two bytes
    my $url  = "https://api.oldserver.com/v2/users";
    my $data = "\x01\x02" . $url . "\x00" x 10 . "\x03\x04";
    my $f    = tmp_with($data);

    capture { patch_literal($f, "oldserver", "new", text_mode => 0) };

    my $result = read_file($f);

    # Total file length unchanged
    is(length($result), length($data), 'binary literal: file size unchanged');

    # "oldserver" is gone
    unlike($result, qr/oldserver/, 'binary literal: old string absent');

    # ".com" still intact (NUL not inserted mid-URL)
    like($result, qr/\.com/, 'binary literal: .com still present');

    # NUL bytes should come after .com in the URL region
    my $url_start = index($result, "https://api.new");
    ok($url_start >= 0, 'binary literal: new URL prefix present');
    my $nul_pos = index($result, "\x00", $url_start);
    my $com_pos = index($result, ".com", $url_start);
    ok($com_pos < $nul_pos, 'binary literal: NUL padding follows .com (tail padding)');
}

# ---------------------------------------------------------------------------
# patch_literal — no match warns, returns 0
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    my ($out, $err) = capture { patch_literal($f, "NOPE", "x", text_mode => 1) };
    like($err, qr/\[warn\]/, 'literal: warns on no match');
    is(read_file($f), "hello world", 'literal: file unchanged on no match');
}

# ---------------------------------------------------------------------------
# patch_literal — dry_run does not write
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    capture { patch_literal($f, "world", "earth", text_mode => 1, dry_run => 1) };
    is(read_file($f), "hello world", 'literal: dry_run leaves file unchanged');
}

# ---------------------------------------------------------------------------
# patch_regex — text mode
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("foo123bar");
    capture { patch_regex($f, 's/(\d+)/[$1]/', text_mode => 1) };
    is(read_file($f), "foo[123]bar", 'regex text: capture group in replacement');
}

# ---------------------------------------------------------------------------
# patch_regex — global flag
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("aXbXcX");
    capture { patch_regex($f, 's/X/Y/g', text_mode => 1) };
    is(read_file($f), "aYbYcY", 'regex text global: all matches replaced');
}

# ---------------------------------------------------------------------------
# patch_regex — binary mode (NUL tail padding)
# ---------------------------------------------------------------------------

{
    my $url  = "https://api.oldserver.com/v2/users";
    my $data = "\x01\x02" . $url . "\x00" x 10 . "\x03\x04";
    my $f    = tmp_with($data);

    capture { patch_regex($f, 's|oldserver|new|', text_mode => 0) };

    my $result = read_file($f);

    is(length($result), length($data), 'regex binary: file size unchanged');
    unlike($result, qr/oldserver/,     'regex binary: old pattern absent');
    like($result,   qr/\.com/,         'regex binary: .com still intact');

    my $url_start = index($result, "https://api.new");
    my $nul_pos   = index($result, "\x00", $url_start);
    my $com_pos   = index($result, ".com",  $url_start);
    ok($com_pos < $nul_pos, 'regex binary: NUL padding follows .com');
}

# ---------------------------------------------------------------------------
# patch_regex — replacement too long in binary mode
# ---------------------------------------------------------------------------

{
    my $data = "\x01" . "short_str_here" . "\x00" x 5 . "\x01";
    my $f    = tmp_with($data);
    eval { capture { patch_regex($f, 's/short/this_is_much_longer_than_short/', text_mode => 0) } };
    like($@, qr/\[error\]/, 'regex binary: dies when replacement too long');
}

# ---------------------------------------------------------------------------
# patch_regex — no match warns
# ---------------------------------------------------------------------------

{
    my $f = tmp_with("hello world");
    my ($out, $err) = capture { patch_regex($f, 's/ZZZNOPE/x/', text_mode => 1) };
    like($err, qr/\[warn\]/, 'regex: warns on no match');
}
