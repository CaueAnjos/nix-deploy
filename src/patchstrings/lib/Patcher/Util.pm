package Patcher::Util;

use strict;
use warnings;
use Exporter 'import';

our @EXPORT_OK = qw(die_err warn_err);

sub die_err  { die  "[error]: $_[0]\n" }
sub warn_err { warn "[warn]: $_[0]\n"  }

1;
