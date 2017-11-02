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
use JSON::Any;
use File::Temp;
use Test::Exception;
use lib 'lib';
use Izel;

my $izel = Izel->new(
    output_dir => File::Temp::tempdir( CLEANUP => 1 ),
    auth_string => 'mock_auth_string=keyandaccess_token=mock_access_token',
);
isa_ok($izel, 'Izel');

subtest 'Non-uploaded SKUs' => sub {
    lives_ok { $izel->get_dbh } 'Got a DBH';

    {
        my @skus = $izel->get_skus_not_uploaded( page_size => 7 );
        is scalar @skus, 7, '7 SKUs';
    }

    {
        my @skus2 = $izel->get_skus_not_uploaded();
        is scalar @skus2, 1000, '1000 SKUs';
    }
}
