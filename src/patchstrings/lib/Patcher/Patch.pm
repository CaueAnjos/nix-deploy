package Patcher::Patch;

use strict;
use warnings;
use Exporter 'import';
use Patcher::File   qw(read_file write_file);
use Patcher::Regex  qw(parse_subst);
use Patcher::Binary qw(build_literal_patches build_regex_patches validate_patches apply_patches);
use Patcher::Util   qw(warn_err);

our @EXPORT_OK = qw(patch_literal patch_regex);

# ---------------------------------------------------------------------------
# patch_literal($file, $old, $new, %opts) -> $count
#
# Applies a literal string replacement.
# Options: text_mode (bool), dry_run (bool), verbose (bool).
# ---------------------------------------------------------------------------
sub patch_literal {
    my ($file, $old, $new, %opts) = @_;

    my $text_mode = $opts{text_mode} // 0;
    my $dry_run   = $opts{dry_run}   // 0;
    my $verbose   = $opts{verbose}   // 0;

    my $data    = read_file($file);
    my @patches = build_literal_patches($data, $old, $new, $text_mode);

    if (!@patches) {
        warn_err("'$old' not found in '$file'");
        return 0;
    }

    validate_patches(\@patches);

    if ($verbose || $dry_run) {
        for my $p (@patches) {
            printf "[patch] offset=%d len=%d old=%s new=%s\n",
                $p->{offset}, $p->{length},
                _quote($p->{old}), _quote($p->{new});
        }
    }

    return 0 if $dry_run;

    my ($new_data, $count) = apply_patches($data, \@patches, $text_mode);
    write_file($file, $new_data);
    print "$file: '$old' -> '$new' ($count occurrence(s) patched)\n";
    return $count;
}

# ---------------------------------------------------------------------------
# patch_regex($file, $expr, %opts) -> $count
#
# Applies a s/// substitution expression.
# Options: text_mode (bool), dry_run (bool), verbose (bool).
# ---------------------------------------------------------------------------
sub patch_regex {
    my ($file, $expr, %opts) = @_;

    my $text_mode = $opts{text_mode} // 0;
    my $dry_run   = $opts{dry_run}   // 0;
    my $verbose   = $opts{verbose}   // 0;

    my $subst   = parse_subst($expr);
    my $data    = read_file($file);
    my @patches = build_regex_patches($data, $subst, $text_mode);

    if (!@patches) {
        warn_err("pattern matched nothing in '$file'");
        return 0;
    }

    validate_patches(\@patches);

    if ($verbose || $dry_run) {
        for my $p (@patches) {
            printf "[patch] offset=%d len=%d old=%s new=%s\n",
                $p->{offset}, $p->{length},
                _quote($p->{old}), _quote($p->{new});
        }
    }

    return 0 if $dry_run;

    my ($new_data, $count) = apply_patches($data, \@patches, $text_mode);
    write_file($file, $new_data);
    print "$file: applied $count substitution(s) via $expr\n";
    return $count;
}

# ---------------------------------------------------------------------------
# _quote($str) -> printable representation (NULs shown as \0)
# ---------------------------------------------------------------------------
sub _quote {
    my ($s) = @_;
    $s =~ s/\x00/\\0/g;
    return $s;
}

1;
