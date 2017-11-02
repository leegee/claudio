use strict;
use warnings;

use Log::Log4perl ':easy';
Log::Log4perl->easy_init({
    file => 'STDERR',
    level => $TRACE,
    layout => '%M %m%n'
});


use Data::Dumper;
use Test::More;
use Test::Exception;
use JSON::Any;
use lib 'lib';
use Izel;

my $izel = Izel->new();
isa_ok($izel, 'Izel');

warn $izel->lookup('ARTHR');
