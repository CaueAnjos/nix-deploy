package Patcher::Regex;

use strict;
use warnings;
use Exporter 'import';
use Patcher::Util qw(die_err);

our @EXPORT_OK = qw(parse_subst expand_replacement);

# ---------------------------------------------------------------------------
# parse_subst($expr) -> { pattern=>, replacement=>, flags=>, re=> }
#
# Parses a substitution expression of the form:
#   s DELIM pattern DELIM replacement DELIM flags
# where DELIM can be any non-word character (/, |, #, …).
# Returns a hashref with the parsed components plus a compiled qr// object.
# ---------------------------------------------------------------------------
sub parse_subst {
    my ($expr) = @_;

    unless ($expr =~ /\As(.)/) {
        die_err("patch expression must start with 's', got: $expr");
    }
    my $delim = quotemeta($1);

    unless ($expr =~ /\As${delim}((?:[^\\]|\\.)*?)${delim}((?:[^\\]|\\.)*?)${delim}([gimsxe]*)\z/) {
        die_err("cannot parse substitution expression: $expr");
    }
    my ($pattern, $replacement, $flags) = ($1, $2, $3);

    # g and e are substitution-only flags — not valid inside qr//
    (my $qr_flags = $flags) =~ s/[ge]//g;
    my $re = eval { $qr_flags ? qr/(?$qr_flags:$pattern)/ : qr/$pattern/ };
    die_err("invalid regex in patch expression: $@") if $@;

    return {
        pattern     => $pattern,
        replacement => $replacement,
        flags       => $flags,
        re          => $re,
    };
}

# ---------------------------------------------------------------------------
# expand_replacement($template, @captures) -> $string
#
# Expands a replacement string, substituting:
#   $1..$9          -> positional captures
#   ${name}         -> named captures (via %+)
#   $ENV_VAR        -> environment variables (uppercase + underscore)
# ---------------------------------------------------------------------------
sub expand_replacement {
    my ($rep, @caps) = @_;
    $rep =~ s/\$\{(\w+)\}/defined $+{$1} ? $+{$1} : ''/ge;
    $rep =~ s/\$(\d)/defined $caps[$1-1] ? $caps[$1-1] : ''/ge;
    $rep =~ s/\$([A-Z_][A-Z0-9_]*)/defined $ENV{$1} ? $ENV{$1} : "\$$1"/ge;
    return $rep;
}

1;
