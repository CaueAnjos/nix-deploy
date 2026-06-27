use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 12;

use Patcher::Regex qw(parse_subst expand_replacement);

# ---------------------------------------------------------------------------
# parse_subst — valid expressions
# ---------------------------------------------------------------------------

{
    my $s = parse_subst('s/foo/bar/');
    is($s->{pattern},     'foo', 'pattern parsed');
    is($s->{replacement}, 'bar', 'replacement parsed');
    is($s->{flags},       '',    'empty flags');
    isa_ok($s->{re}, 'Regexp',   'compiled qr//');
}

{
    my $s = parse_subst('s|old|new|gi');
    is($s->{flags}, 'gi', 'pipe delimiter + flags');
}

{
    my $s = parse_subst('s#foo#bar#');
    is($s->{pattern}, 'foo', 'hash delimiter works');
}

# ---------------------------------------------------------------------------
# parse_subst — invalid expressions
# ---------------------------------------------------------------------------

{
    eval { parse_subst('not_a_subst') };
    like($@, qr/\[error\].*must start with 's'/, 'rejects non-s expression');
}

{
    eval { parse_subst('s/unclosed') };
    like($@, qr/\[error\].*cannot parse/, 'rejects malformed expression');
}

# ---------------------------------------------------------------------------
# expand_replacement
# ---------------------------------------------------------------------------

{
    my $rep = expand_replacement('$1-$2', 'hello', 'world');
    is($rep, 'hello-world', 'positional captures expanded');
}

{
    local $ENV{MY_VAR} = 'injected';
    my $rep = expand_replacement('prefix-$MY_VAR-suffix');
    is($rep, 'prefix-injected-suffix', 'env vars expanded');
}

{
    # Undefined positional capture -> empty string
    my $rep = expand_replacement('[$1][$2]', 'only_one');
    is($rep, '[only_one][]', 'undefined positional capture becomes empty string');
}

{
    # $9 when only 2 captures
    my $rep = expand_replacement('$9', 'a', 'b');
    is($rep, '', 'out-of-range capture becomes empty string');
}
