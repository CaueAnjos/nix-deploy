package Patcher::Find;

use strict;
use warnings;
use Exporter 'import';
use File::Find ();
use Patcher::File qw(read_file);
use Patcher::Util qw(die_err);

our @EXPORT_OK = qw(find_strings locate_printable_strings run_find);

# Minimum printable-ASCII run length, same as strings(1) default.
use constant MIN_RUN => 4;

# ---------------------------------------------------------------------------
# find_strings($data, $regex) -> @matches
#
# Extracts printable-ASCII runs of MIN_RUN+ chars (mimicking strings(1)) from
# raw binary $data, then returns every match of $regex within those runs.
# Duplicates are suppressed; order is the order of first occurrence.
# ---------------------------------------------------------------------------
sub find_strings {
    my ($data, $regex) = @_;
    my %seen;
    my @matches;
    while ($data =~ /[\x20-\x7e]{@{[MIN_RUN]},}/g) {
        my $run = $&;
        while ($run =~ /($regex)/g) {
            my $m = $1;
            push @matches, $m unless $seen{$m}++;
        }
    }
    return @matches;
}

# ---------------------------------------------------------------------------
# locate_printable_strings($data) -> @({ offset=>, text=> }, ...)
#
# Returns every printable-ASCII run of MIN_RUN+ bytes with its byte offset.
# Used by Binary.pm to build patch objects safely.
# ---------------------------------------------------------------------------
sub locate_printable_strings {
    my ($data) = @_;
    my @runs;
    while ($data =~ /[\x20-\x7e]{@{[MIN_RUN]},}/g) {
        push @runs, { offset => $-[0], text => $& };
    }
    return @runs;
}

# ---------------------------------------------------------------------------
# run_find($regex_str, $path) -> exits after printing results
# ---------------------------------------------------------------------------
sub run_find {
    my ($regex_str, $path) = @_;

    unless (defined $regex_str && length $regex_str
         && defined $path      && length $path) {
        die_err("usage: patcher.pl --find <regex> <path>");
    }

    my $re = eval { qr/$regex_str/ };
    die_err("invalid regex '$regex_str': $@") if $@;

    my %all;

    if (-f $path) {
        my $data = read_file($path);
        $all{$_}++ for find_strings($data, $re);
    } elsif (-d $path) {
        File::Find::find({
            wanted => sub {
                return unless -f $_;
                my $data = read_file($_);
                $all{$_}++ for find_strings($data, $re);
            },
            no_chdir => 1,
        }, $path);
    } else {
        die_err("'$path' needs to be a directory or file");
    }

    print "$_\n" for sort keys %all;
}

1;
