package Patcher::CLI;

use strict;
use warnings;
use Exporter 'import';
use Getopt::Long qw(:config no_auto_abbrev pass_through);
use Patcher::Find  qw(run_find);
use Patcher::Patch qw(patch_literal patch_regex);
use Patcher::Util  qw(die_err);

our @EXPORT_OK = qw(run);

# ---------------------------------------------------------------------------
# run(\@argv)
#
# Entry point: parses global options, then dispatches to:
#   --find    -> Patcher::Find::run_find
#   --regex   -> Patcher::Patch::patch_regex
#   (default) -> Patcher::Patch::patch_literal
# ---------------------------------------------------------------------------
sub run {
    my ($argv) = @_;
    local @ARGV = @$argv;

    # -----------------------------------------------------------------------
    # --find mode
    # -----------------------------------------------------------------------
    if (@ARGV && $ARGV[0] eq '--find') {
        shift @ARGV;
        my ($regex, $path) = @ARGV;
        run_find($regex, $path);
        return;
    }

    # -----------------------------------------------------------------------
    # Patch modes — collect flags first
    # -----------------------------------------------------------------------
    my $use_regex  = 0;
    my $text_mode  = 0;
    my $dry_run    = 0;
    my $verbose    = 0;
    my $patch_expr;

    # Manual flag scan so we can grab --regex's argument inline.
    while (@ARGV && $ARGV[0] =~ /^--(regex|text|dry-run|verbose)$/) {
        my $flag = shift @ARGV;
        if ($flag eq '--regex') {
            $use_regex  = 1;
            $patch_expr = shift @ARGV
                or die_err("--regex requires a substitution expression, e.g. 's|old|new|g'");
        } elsif ($flag eq '--text') {
            $text_mode = 1;
        } elsif ($flag eq '--dry-run') {
            $dry_run = 1;
        } elsif ($flag eq '--verbose') {
            $verbose = 1;
        }
    }

    my %common = (
        text_mode => $text_mode,
        dry_run   => $dry_run,
        verbose   => $verbose,
    );

    # -----------------------------------------------------------------------
    # Regex patch mode
    # -----------------------------------------------------------------------
    if ($use_regex) {
        my $file = shift @ARGV
            or die_err("missing <file> argument");
        patch_regex($file, $patch_expr, %common);
        return;
    }

    # -----------------------------------------------------------------------
    # Literal patch mode
    # -----------------------------------------------------------------------
    my ($old, $new, $file) = @ARGV;

    unless (defined $old && defined $new && defined $file) {
        die_err(
            "usage:\n"
          . "  patcher.pl <old> <new> <file>\n"
          . "  patcher.pl [--text] [--dry-run] [--verbose] --regex 's|PAT|REP|flags' <file>\n"
          . "  patcher.pl --find <regex> <path>"
        );
    }

    patch_literal($file, $old, $new, %common);
}

1;
