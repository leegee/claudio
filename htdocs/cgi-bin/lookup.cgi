#!perl
use strict;
use warnings;

use lib 'lib';
use Izel;

my $izel = Izel->new();

print "Content-type: text/plain\n\n",
        $izel->lookup($ENV{QUERY_STRING}),
        "\n";

exit;
