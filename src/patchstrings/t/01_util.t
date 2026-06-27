use strict;
use warnings;
use FindBin qw($RealBin);
use lib "$RealBin/../lib";
use Test::More tests => 2;

use Patcher::Util qw(die_err warn_err);

# die_err should die with the formatted message
eval { die_err("something went wrong") };
like($@, qr/\[error\]: something went wrong/, 'die_err formats message');

# warn_err should warn (captured via $SIG{__WARN__})
my $warning;
local $SIG{__WARN__} = sub { $warning = $_[0] };
warn_err("heads up");
like($warning, qr/\[warn\]: heads up/, 'warn_err formats message');
