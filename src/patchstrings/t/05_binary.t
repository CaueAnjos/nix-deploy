use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 34;

use Patcher::Binary qw(
    build_literal_patches
    build_regex_patches
    validate_patches
    apply_patches
);
use Patcher::Regex  qw(parse_subst);
use Patcher::Find   qw(locate_printable_strings);

# ---------------------------------------------------------------------------
# Helper: build a binary buffer with a known printable string
# ---------------------------------------------------------------------------
sub make_binary {
    my ($str, $padding) = @_;
    $padding //= 10;
    return "\x01\x02" . $str . ("\x00" x $padding) . "\x03\x04";
}

# ---------------------------------------------------------------------------
# build_literal_patches — binary mode
# ---------------------------------------------------------------------------

{
    my $data = make_binary("https://api.oldserver.com/v2/users");
    my @patches = build_literal_patches($data, "oldserver", "new", 0);
    is(scalar @patches, 1, 'literal binary: one patch object');

    my $p = $patches[0];
    ok(defined $p->{offset},             'patch has offset');
    ok(defined $p->{length},             'patch has length');
    like($p->{old}, qr/oldserver/,       'patch old contains search term');
    unlike($p->{new}, qr/oldserver/,     'patch new does not contain old term');
    like($p->{new}, qr/new/,             'patch new contains replacement');
    is(length($p->{new}), length($p->{old}), 'binary patch preserves length via NUL padding');

    # NUL bytes are at the end, not in the middle of the URL
    my $idx_nul = index($p->{new}, "\x00");
    my $idx_com = index($p->{new}, ".com");
    ok($idx_com < $idx_nul || $idx_nul == -1,
       'NUL padding comes after .com, not before it');
}

# ---------------------------------------------------------------------------
# build_literal_patches — binary mode with pad_str => "/" (path-safe fill)
#
# Regression test for the "Perl SV / Ruby RString" bug: when a shorter
# replacement is padded with NUL, readers that track an explicit string
# length (rather than relying on NUL-termination) end up with a truncated
# "logical" string followed by literal NUL bytes. Padding with a printable,
# path-neutral filler like "/" avoids introducing that discrepancy: the
# patched region stays entirely printable ASCII, so a naive length-based
# reader and a NUL-terminated reader agree on the content.
# ---------------------------------------------------------------------------

{
    my $str  = "/nix/store/abcdefghijklmnopqrstuvwxyz0123456-perl-5.36.0";
    my $data = make_binary($str);
    my @patches = build_literal_patches($data, $str, "/opt/myapp", 0, "/");
    is(scalar @patches, 1, 'pad_str literal: one patch object');

    my $p = $patches[0];
    is(length($p->{new}), length($p->{old}), 'pad_str literal: length preserved');
    ok(index($p->{new}, "\x00") == -1, 'pad_str literal: no NUL introduced');
    like($p->{new}, qr{^/opt/myapp/+$}, 'pad_str literal: padded with trailing slashes');

    # Re-scanning the patched buffer as printable-ASCII runs should report
    # the SAME run length as before patching — i.e. no apparent truncation
    # for any consumer that infers length from the printable run itself.
    my ($new_data) = apply_patches($data, \@patches, 0);
    my @orig_runs  = locate_printable_strings($data);
    my @new_runs   = locate_printable_strings($new_data);
    is($new_runs[0]{text}, $p->{new}, 'pad_str literal: patched run matches patch');
    is(length($new_runs[0]{text}), length($orig_runs[0]{text}),
       'pad_str literal: printable run length unchanged after patch');
}

# ---------------------------------------------------------------------------
# build_literal_patches — text mode (no NUL padding, length may change)
# ---------------------------------------------------------------------------

{
    my $data = "hello world";
    my @patches = build_literal_patches($data, "world", "universe", 1);
    is(scalar @patches, 1, 'literal text: one patch');
    is($patches[0]{new}, "universe", 'text mode: no NUL padding');
}

# ---------------------------------------------------------------------------
# build_literal_patches — multiple occurrences
# ---------------------------------------------------------------------------

{
    my $data = "foo_longname\x00foo_longname extra text";
    my @patches = build_literal_patches($data, "foo", "bar", 0);
    ok(scalar @patches >= 1, 'multiple occurrences generate patches');
}

# ---------------------------------------------------------------------------
# build_literal_patches — no match
# ---------------------------------------------------------------------------

{
    my $data = "nothing here at all";
    my @patches = build_literal_patches($data, "ZZZNOMATCH", "x", 1);
    is(scalar @patches, 0, 'no match returns empty patch list');
}

# ---------------------------------------------------------------------------
# build_literal_patches — binary: new longer than old (should die)
# ---------------------------------------------------------------------------

{
    my $data = make_binary("short_string_here");
    eval { build_literal_patches($data, "short", "much_longer_replacement_string", 0) };
    like($@, qr/\[error\]/, 'binary: dies when replacement is too long');
}

# ---------------------------------------------------------------------------
# build_regex_patches — binary mode
# ---------------------------------------------------------------------------

{
    my $data = make_binary("https://api.oldserver.com/v2/users");
    my $subst = parse_subst('s|oldserver|new|');
    my @patches = build_regex_patches($data, $subst, 0);
    is(scalar @patches, 1, 'regex binary: one patch object');

    my $p = $patches[0];
    is(length($p->{new}), length($p->{old}), 'regex binary: length preserved');
    like($p->{new}, qr/new/,        'regex binary: replacement present');
    unlike($p->{new}, qr/oldserver/, 'regex binary: old text replaced');

    # Verify NUL padding is at tail of string (after .com)
    my $idx_nul = index($p->{new}, "\x00");
    my $idx_com = index($p->{new}, ".com");
    ok($idx_com < $idx_nul || $idx_nul == -1,
       'regex binary: NUL at tail, not mid-string');
}

# ---------------------------------------------------------------------------
# build_regex_patches — binary mode with pad_str => "/" (path-safe fill)
# ---------------------------------------------------------------------------

{
    my $str  = "/nix/store/abcdefghijklmnopqrstuvwxyz0123456-perl-5.36.0";
    my $data = make_binary($str);
    my $subst = parse_subst('s|/nix/store/[a-z0-9]+-perl-5\.36\.0|/opt/myapp|');
    my @patches = build_regex_patches($data, $subst, 0, "/");
    is(scalar @patches, 1, 'pad_str regex: one patch object');

    my $p = $patches[0];
    is(length($p->{new}), length($p->{old}), 'pad_str regex: length preserved');
    ok(index($p->{new}, "\x00") == -1, 'pad_str regex: no NUL introduced');
    like($p->{new}, qr{^/opt/myapp/+$}, 'pad_str regex: padded with trailing slashes');
}

# ---------------------------------------------------------------------------
# validate_patches — overlapping patches
# ---------------------------------------------------------------------------

{
    my @patches = (
        { offset => 0,  length => 10, old => 'a' x 10, new => 'b' x 10 },
        { offset => 5,  length => 10, old => 'c' x 10, new => 'd' x 10 },
    );
    eval { validate_patches(\@patches) };
    like($@, qr/\[error\].*overlap/, 'validate_patches dies on overlapping patches');
}

{
    my @patches = (
        { offset => 0,  length => 10, old => 'a' x 10, new => 'b' x 10 },
        { offset => 10, length => 5,  old => 'c' x 5,  new => 'd' x 5  },
    );
    ok(eval { validate_patches(\@patches) }, 'validate_patches passes for adjacent patches');
}

# ---------------------------------------------------------------------------
# apply_patches — basic functionality
# ---------------------------------------------------------------------------

{
    my $data = "hello world";
    my @patches = (
        { offset => 6, length => 5, old => 'world', new => 'earth' },
    );
    my ($result, $count) = apply_patches($data, \@patches, 1);
    is($result, "hello earth", 'apply_patches: basic text replacement');
    is($count,  1,             'apply_patches: correct count');
}

{
    # Two non-overlapping patches applied in reverse offset order
    my $data = "aaa bbb ccc";
    my @patches = (
        { offset => 0, length => 3, old => 'aaa', new => 'AAA' },
        { offset => 8, length => 3, old => 'ccc', new => 'CCC' },
    );
    my ($result, $count) = apply_patches($data, \@patches, 1);
    is($result, "AAA bbb CCC", 'apply_patches: two non-overlapping patches');
    is($count,  2,             'apply_patches: count = 2');
}
