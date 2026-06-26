#!/usr/bin/env perl
use strict;
use warnings;
use File::Find;
use Getopt::Long qw(:config no_auto_abbrev pass_through);

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

sub die_err { die "[error]: $_[0]\n" }

sub strings_grep {
    my ($path, $regex) = @_;
    open(my $fh, '<:raw', $path) or die_err("cannot open '$path': $!");
    my $data = do { local $/; <$fh> };
    close $fh;

    # Extract printable-ASCII runs of 4+ chars (mimics strings(1))
    my %seen;
    my @matches;
    while ($data =~ /[\x20-\x7e]{4,}/g) {
        my $run = $&;
        while ($run =~ /($regex)/g) {
            my $m = $1;
            push @matches, $m unless $seen{$m}++;
        }
    }
    return @matches;
}

# ---------------------------------------------------------------------------
# --find mode
# ---------------------------------------------------------------------------

if (@ARGV && $ARGV[0] eq '--find') {
    shift @ARGV;
    my ($regex, $path);
    GetOptions('find' => sub {}) or die_err("bad options");
    ($regex, $path) = @ARGV;

    unless (defined $regex && length $regex && defined $path && length $path) {
        die_err("usage: $0 --find <regex> <path>");
    }

    # Compile regex early so we fail fast on a bad pattern
    my $re = eval { qr/$regex/ };
    die_err("invalid regex '$regex': $@") if $@;

    my %all;

    if (-f $path) {
        $all{$_}++ for strings_grep($path, $re);
    } elsif (-d $path) {
        find({
            wanted => sub {
                return unless -f $_;
                $all{$_}++ for strings_grep($_, $re);
            },
            no_chdir => 1,
        }, $path);
    } else {
        die_err("'$path' needs to be a directory or file");
    }

    print "$_\n" for sort keys %all;
    exit 0;
}

# ---------------------------------------------------------------------------
# patch mode  (literal or regex)
#
# Literal usage:  patcher.pl <old> <new> <file>
# Regex  usage:   patcher.pl [--text] --regex 's|PATTERN|REPLACEMENT|flags' <file>
#
# --text  disables NUL-padding and the length constraint (safe for text files).
#         Binary files are NUL-padded by default so offsets stay stable.
# ---------------------------------------------------------------------------

my $use_regex = 0;
my $text_mode = 0;
my $patch_expr;

# Peek at argv to decide mode before full parse
while (@ARGV && $ARGV[0] =~ /^--(regex|text)$/) {
    my $flag = shift @ARGV;
    if ($flag eq '--regex') {
        $use_regex  = 1;
        $patch_expr = shift @ARGV
            or die_err("--regex requires a substitution expression, e.g. 's|old|new|g'");
    } elsif ($flag eq '--text') {
        $text_mode = 1;
    }
}

# ---------------------------------------------------------------------------
# shared: validate and open a target file (any regular file, not just executables)
# ---------------------------------------------------------------------------
sub open_target {
    my ($path) = @_;
    -e $path or die_err("'$path' does not exist");
    -f $path or die_err("'$path' is not a regular file");
    -r $path or die_err("'$path' is not readable");
    -w $path or die_err("'$path' is not writable");
    open(my $fh, '<:raw', $path) or die_err("cannot open '$path' for reading: $!");
    my $data = do { local $/; <$fh> };
    close $fh;
    return $data;
}

sub write_target {
    my ($path, $data) = @_;
    open(my $fh, '>:raw', $path) or die_err("cannot open '$path' for writing: $!");
    print $fh $data;
    close $fh;
}

# ---------------------------------------------------------------------------
# shared: expand replacement string ($1..$9, named captures, env vars)
# ---------------------------------------------------------------------------
sub expand_replacement {
    my ($rep, @caps) = @_;
    $rep =~ s/\$\{(\w+)\}/defined $+{$1} ? $+{$1} : ''/ge;
    $rep =~ s/\$(\d)/defined $caps[$1-1] ? $caps[$1-1] : ''/ge;
    $rep =~ s/\$([A-Z_][A-Z0-9_]*)/defined $ENV{$1} ? $ENV{$1} : "\$$1"/ge;
    return $rep;
}

if ($use_regex) {
    # -----------------------------------------------------------------------
    # Regex patch mode
    # -----------------------------------------------------------------------
    my $file = shift @ARGV or die_err("missing <file> argument");
    my $data = open_target($file);

    # Parse the substitution expression: s DELIM pattern DELIM replacement DELIM flags
    # Delimiter may be any non-word char (|, /, #, …)
    unless ($patch_expr =~ /\As(.)/) {
        die_err("patch expression must start with 's', got: $patch_expr");
    }
    my $delim = quotemeta($1);
    unless ($patch_expr =~ /\As${delim}((?:[^\\]|\\.)*?)${delim}((?:[^\\]|\\.)*?)${delim}([gimsxe]*)\z/) {
        die_err("cannot parse substitution expression: $patch_expr");
    }
    my ($pattern, $replacement, $flags) = ($1, $2, $3);

    # g and e are substitution-only flags — not valid inside qr//
    (my $qr_flags = $flags) =~ s/[ge]//g;
    my $re = eval { $qr_flags ? qr/(?$qr_flags:$pattern)/ : qr/$pattern/ };
    die_err("invalid regex in patch expression: $@") if $@;

    my $count = 0;
    $data =~ s{$re}{
        my $matched   = $&;
        my $len_match = length($matched);
        my $rep       = expand_replacement($replacement, $1,$2,$3,$4,$5,$6,$7,$8,$9);
        my $len_rep   = length($rep);

        if (!$text_mode && $len_rep > $len_match) {
            die_err("replacement '$rep' (len $len_rep) is longer than match '$matched' (len $len_match); "
                  . "cannot patch binary safely (use --text to allow size changes)");
        }
        $count++;
        $text_mode
            ? $rep
            : $rep . ("\x00" x ($len_match - $len_rep));
    }ge;

    if ($count == 0) {
        warn "[warn]: pattern matched nothing in '$file'\n";
    } else {
        write_target($file, $data);
        print "$file: applied $count substitution(s) via $patch_expr\n";
    }

} else {
    # -----------------------------------------------------------------------
    # Literal patch mode  (original behaviour, hardened)
    # -----------------------------------------------------------------------
    my ($old, $new, $file) = @ARGV;

    unless (defined $old && defined $new && defined $file) {
        die_err("usage:\n"
              . "  $0 <old> <new> <file>\n"
              . "  $0 [--text] --regex 's|PAT|REP|flags' <file>\n"
              . "  $0 --find <regex> <path>");
    }

    my $size_old = length($old);
    my $size_new = length($new);

    if (!$text_mode && $size_old < $size_new) {
        die_err("new string (len $size_new) must be equal to or shorter than old string (len $size_old) "
              . "for binary patching (use --text to allow size changes)");
    }

    my $data  = open_target($file);
    my $count = 0;

    $data =~ s{\Q$old\E}{
        $count++;
        $text_mode
            ? $new
            : $new . ("\x00" x ($size_old - $size_new))
    }ge;

    if ($count == 0) {
        warn "[warn]: '$old' not found in '$file'\n";
    } else {
        write_target($file, $data);
        print "$file: '$old' -> '$new' ($count occurrence(s) patched)\n";
    }
}
