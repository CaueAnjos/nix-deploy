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
    my $pad_str    = "\x00";
    my $fill_str;
    my $patch_expr;

    # Manual flag scan so we can grab --regex's/--pad-str's/--fill-str's
    # argument inline.
    while (@ARGV && $ARGV[0] =~ /^--(regex|text|dry-run|verbose|pad-str|fill-str)$/) {
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
        } elsif ($flag eq '--pad-str') {
            $pad_str = shift @ARGV;
            die_err("--pad-str requires a non-empty string argument")
                unless defined $pad_str && length $pad_str;
            die_err("--pad-str must be exactly one character")
                unless length($pad_str) == 1;
        } elsif ($flag eq '--fill-str') {
            $fill_str = shift @ARGV;
            die_err("--fill-str requires a non-empty string argument")
                unless defined $fill_str && length $fill_str;
            die_err("--fill-str must be exactly one character")
                unless length($fill_str) == 1;
        }
    }

    die_err("--pad-str and --fill-str are mutually exclusive; specify only one")
        if defined $fill_str && $pad_str ne "\x00";

    my %common = (
        text_mode => $text_mode,
        dry_run   => $dry_run,
        verbose   => $verbose,
        pad_str   => $pad_str,
        fill_str  => $fill_str,
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
          . "  patchstrings [--pad-str <s>|--fill-str <s>] <old> <new> <file>\n"
          . "  patchstrings [--text] [--dry-run] [--verbose] [--pad-str <s>|--fill-str <s>] --regex 's|PAT|REP|flags' <file>\n"
          . "  patchstrings --find <regex> <path>\n"
          . "\n"
          . "  --pad-str <s>   binary mode only, 1 character: repeat <s> (default NUL)\n"
          . "                  to fill the gap left by a shorter replacement, at the\n"
          . "                  TAIL of the enclosing printable-ASCII run. Use a\n"
          . "                  printable, semantically-neutral value (e.g. '/' for\n"
          . "                  path-like strings) to avoid corrupting runtimes that\n"
          . "                  store an explicit string length (Perl SVs, Ruby\n"
          . "                  RStrings, etc.) instead of relying on NUL-termination.\n"
          . "  --fill-str <s>  binary mode only, 1 character: like --pad-str, but the\n"
          . "                  fill is inserted LOCALLY at the match site (right after\n"
          . "                  the replacement), before any unchanged suffix that\n"
          . "                  follows it in the same run, instead of at the run's\n"
          . "                  tail. Mutually exclusive with --pad-str."
        );
    }

    patch_literal($file, $old, $new, %common);
}

1;
