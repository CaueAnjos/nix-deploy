package Patcher::Binary;

use strict;
use warnings;
use Exporter 'import';
use Patcher::Find  qw(locate_printable_strings);
use Patcher::Regex qw(expand_replacement);
use Patcher::Util  qw(die_err warn_err);

our @EXPORT_OK = qw(
    build_literal_patches
    build_regex_patches
    validate_patches
    apply_patches
);

# ---------------------------------------------------------------------------
# _fill($str, $n) -> string of exactly $n bytes
#
# Repeats (and truncates) $str to fill exactly $n bytes. Shared by both the
# pad_str (tail-of-run padding, see _make_patch) and fill_str (local, at the
# match site — see build_literal_patches/build_regex_patches) mechanisms.
# ---------------------------------------------------------------------------
sub _fill {
    my ($str, $n) = @_;
    return '' if $n <= 0;
    my $len = length($str);
    return substr($str x (int($n / $len) + 1), 0, $n);
}

# ---------------------------------------------------------------------------
# _make_patch($offset, $old, $new, $text_mode, $pad_str) -> \%patch  or  undef
#
# Creates a patch object and pads $new to match len($old) unless in text
# mode, by repeating $pad_str (default "\x00", i.e. NUL padding) to fill the
# gap. Returns undef if the replacement is too long in binary mode.
#
# $pad_str matters for runtimes that store an explicit string length rather
# than relying on NUL-termination (e.g. Perl SVs, Ruby RStrings): padding
# with "\x00" leaves stale bytes inside the "logical" length these readers
# use, corrupting the string. Passing a printable, semantically-neutral
# pad_str (e.g. "/" for path-like strings) avoids that, at the cost of only
# being safe for strings where the filler bytes are harmless (e.g. trailing
# path separators).
# ---------------------------------------------------------------------------
sub _make_patch {
    my ($offset, $old, $new, $text_mode, $pad_str) = @_;
    $pad_str = "\x00" unless defined $pad_str && length $pad_str;

    my $len_old = length($old);
    my $len_new = length($new);

    if (!$text_mode && $len_new > $len_old) {
        return undef;   # caller decides how to surface the error
    }

    my $padded_new = $text_mode
        ? $new
        : $new . _fill($pad_str, $len_old - $len_new);

    return {
        offset => $offset,
        length => $len_old,
        old    => $old,
        new    => $padded_new,
    };
}

# ---------------------------------------------------------------------------
# build_literal_patches($data, $old, $new, $text_mode, $pad_str, $fill_str)
#   -> @patches
#
# In text mode: simple string replacement anywhere in $data.
# In binary mode: only replace within printable-ASCII runs so that padding
# lands at the END of the enclosing string, not inside it. $pad_str (default
# "\x00") is repeated to fill the gap left by a shorter replacement; pass a
# printable, semantically-neutral value (e.g. "/" for path-like strings) to
# avoid corrupting runtimes that store an explicit string length instead of
# relying on NUL-termination.
#
# $fill_str, if defined, changes WHERE the gap is filled: instead of padding
# the tail of the whole enclosing run (pad_str), the fill characters are
# inserted immediately at the match site, before any unchanged suffix that
# follows it in the same run. E.g. for "/nix/store/xxx-hello/bin/hello"
# patched to "/opt/hello": pad_str => "/opt/hello/bin/hello//////"
# (padding at the very end) vs. fill_str => "/opt/hello/////////bin/hello"
# (padding right after the replacement, before "/bin/hello").
# ---------------------------------------------------------------------------
sub build_literal_patches {
    my ($data, $old, $new, $text_mode, $pad_str, $fill_str) = @_;

    my $len_old = length($old);
    my $len_new = length($new);

    if (!$text_mode && $len_new > $len_old) {
        die_err("new string (len $len_new) must be equal to or shorter than "
              . "old string (len $len_old) for binary patching "
              . "(use --text to allow size changes)");
    }

    my @patches;

    if ($text_mode) {
        # Simple global replacement; offsets are not meaningful for text mode.
        my $pos = 0;
        while (($pos = index($data, $old, $pos)) != -1) {
            push @patches, _make_patch($pos, $old, $new, 1);
            $pos += $len_old;
        }
        return @patches;
    }

    # Binary mode: work string-by-string so padding lands at the string tail.
    for my $run (locate_printable_strings($data)) {
        my $text   = $run->{text};
        my $base   = $run->{offset};
        my $inner  = 0;

        while (($inner = index($text, $old, $inner)) != -1) {
            # Patch object covers the whole enclosing printable run so that
            # pad bytes accumulate at the end of the string, not mid-string
            # (unless fill_str is given — see below).
            my $rep = $new;
            if (defined $fill_str) {
                # Close the gap right at the match site so the unchanged
                # suffix that follows stays immediately after the fill,
                # instead of drifting to the tail of the whole run.
                $rep = $new . _fill($fill_str, $len_old - $len_new);
            }

            my $patched_run = $text;
            substr($patched_run, $inner, $len_old) = $rep;

            my $patch = _make_patch($base, $text, $patched_run, 0, $pad_str);
            unless (defined $patch) {
                die_err("replacement makes string longer than original "
                      . "(use --text to allow size changes)");
            }
            push @patches, $patch;

            # Advance past the matched position to find further occurrences.
            $inner += $len_old;
        }
    }

    return @patches;
}

# ---------------------------------------------------------------------------
# build_regex_patches($data, $subst, $text_mode, $pad_str, $fill_str)
#   -> @patches
#
# $subst is the hashref returned by Patcher::Regex::parse_subst().
#
# In text mode: apply the regex to the whole buffer.
# In binary mode: apply per printable-ASCII run, padding the run's tail with
# $pad_str (default "\x00"; see build_literal_patches for rationale), unless
# $fill_str is given — then each match is padded locally, right after its
# own replacement, instead of accumulating at the run's tail. This matters
# in particular when a single run contains multiple concatenated matches
# (e.g. several nix-store references with no separator between them): local
# fill keeps each match's slack next to itself, preserving the boundary with
# whatever follows, rather than pushing all the slack to the very end of the
# run.
# ---------------------------------------------------------------------------
sub build_regex_patches {
    my ($data, $subst, $text_mode, $pad_str, $fill_str) = @_;

    my $re          = $subst->{re};
    my $replacement = $subst->{replacement};
    my $flags       = $subst->{flags};
    my $global      = ($flags =~ /g/);

    my @patches;

    if ($text_mode) {
        # Apply to entire buffer; offsets are tracked manually.
        my $pos = 0;
        while ($data =~ /$re/g) {
            my $matched  = $&;
            my $rep      = expand_replacement($replacement, $1,$2,$3,$4,$5,$6,$7,$8,$9);
            my $offset   = $-[0];
            push @patches, _make_patch($offset, $matched, $rep, 1);
            last unless $global;
        }
        return @patches;
    }

    # Binary mode: process each printable-ASCII run independently.
    for my $run (locate_printable_strings($data)) {
        my $text = $run->{text};
        my $base = $run->{offset};

        # Collect all regex matches within this run.
        my @run_patches;
        while ($text =~ /$re/g) {
            my $matched = $&;
            my $rep     = expand_replacement($replacement, $1,$2,$3,$4,$5,$6,$7,$8,$9);

            if (defined $fill_str) {
                my $gap = length($matched) - length($rep);
                $rep .= _fill($fill_str, $gap) if $gap > 0;
            }

            # Build a patched copy of the whole run.
            my $patched = $text;
            # Replace only this one occurrence (by position) to avoid double-patching.
            substr($patched, $-[0], length($matched)) = $rep;

            my $patch = _make_patch($base, $text, $patched, 0, $pad_str);
            unless (defined $patch) {
                die_err("replacement '$rep' (len " . length($rep) . ") is longer than "
                      . "match '$matched' (len " . length($matched) . "); "
                      . "cannot patch binary safely (use --text to allow size changes)");
            }
            push @run_patches, $patch;
            last unless $global;
        }

        if (@run_patches == 1) {
            push @patches, $run_patches[0];
        } elsif (@run_patches > 1) {
            # Multiple matches in one run: collapse into a single patch that
            # applies all substitutions to the run at once.
            my $patched = $text;
            my $count   = 0;
            $patched =~ s{$re}{
                my $matched = $&;
                my $rep     = expand_replacement($replacement, $1,$2,$3,$4,$5,$6,$7,$8,$9);
                $count++;
                if (defined $fill_str) {
                    my $gap = length($matched) - length($rep);
                    $rep .= _fill($fill_str, $gap) if $gap > 0;
                }
                $rep
            }ge if $global;

            my $patch = _make_patch($base, $text, $patched, 0, $pad_str);
            unless (defined $patch) {
                die_err("collapsed replacement for run is longer than original; "
                      . "cannot patch binary safely (use --text to allow size changes)");
            }
            push @patches, $patch if $count;
        }
    }

    return @patches;
}

# ---------------------------------------------------------------------------
# validate_patches(\@patches) -> 1  (dies on overlap or other problem)
# ---------------------------------------------------------------------------
sub validate_patches {
    my ($patches) = @_;

    # Sort by offset so we can do a single pass for overlap detection.
    my @sorted = sort { $a->{offset} <=> $b->{offset} } @$patches;

    for my $i (1 .. $#sorted) {
        my $prev = $sorted[$i - 1];
        my $curr = $sorted[$i];
        my $prev_end = $prev->{offset} + $prev->{length};
        if ($curr->{offset} < $prev_end) {
            die_err(sprintf(
                "overlapping patches at offsets %d (len %d) and %d (len %d)",
                $prev->{offset}, $prev->{length},
                $curr->{offset}, $curr->{length},
            ));
        }
    }

    return 1;
}

# ---------------------------------------------------------------------------
# apply_patches($data, \@patches, $text_mode) -> ($new_data, $count)
#
# Applies patches in reverse offset order (highest offset first) so that
# earlier offsets remain valid.  Text-mode patches may change the buffer
# length; binary-mode patches must not (enforced at build time).
# ---------------------------------------------------------------------------
sub apply_patches {
    my ($data, $patches, $text_mode) = @_;

    my @sorted = sort { $b->{offset} <=> $a->{offset} } @$patches;
    my $count  = 0;

    for my $p (@sorted) {
        substr($data, $p->{offset}, $p->{length}) = $p->{new};
        $count++;
    }

    return ($data, $count);
}

1;
