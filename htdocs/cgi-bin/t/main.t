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
use HTTP::Response;
use Test::Exception;
use Test::LWP::UserAgent;
use File::Temp;
use JSON::Any;
use lib 'lib';
use Izel;

my $MOCK_TABLE_ID = 999;

my $MOCK_RES_CONTENT = {
    _create_table_on_google => {tableId => $MOCK_TABLE_ID},
    gsql => {rows => [[$MOCK_TABLE_ID]]}
};

my $table;
my $izel = newTestable();

subtest 'DB scheme init' => sub {
    unlink $Izel::CONFIG->{db_path} if -e $Izel::CONFIG->{db_path};

    lives_ok { $izel->get_dbh } 'get';
    ok $izel->{dbh}, 'exists';
};

subtest 'setup' => sub {
    is $izel->ingest_sku_from_csv( path => 'data/small.csv'), 18, 'import';
    is_deeply $izel->get_initials(), ['A', 'S'], 'Initials';
};

subtest 'create_fusion_tables' => sub {
    @_ = @{ $izel->create_fusion_tables };
    $table = $_[0];
    test_table_obj(@_);
    is_deeply $table->{skus}, ['ARTHR', 'SCSC'], 'skus';
    is $table->{count}, 18, 'count';
    is $table->{name}, 'Merged Table #0 (ARTHR - SCSC)', 'name';
    is $table->{index_number}, 0, 'index_number';

    is $izel->is_sku_valid( $table->{skus}->[0] ), 1, 'is_sku_valid' or die;
    is $izel->is_sku_published( $table->{skus}->[0] ), 1, 'is_sku_published' or die Dumper $table->{skus}->[0];

    test_data_in_db($izel);
    $izel->{dbh}->disconnect;
};

subtest 'map_some_skus' => sub {
    $izel = newTestable(0);
    test_data_in_db($izel) or die;
    $izel->wipe_google_tables;
    is scalar $izel->{dbh}->selectall_array("
        SELECT DISTINCT sku FROM $Izel::CONFIG->{geosku_table_name}
    "), 2, 'Kept SKUs in DB after wipe' or die;
    is scalar $izel->{dbh}->selectall_array("
        SELECT DISTINCT sku FROM $Izel::CONFIG->{geosku_table_name}
        WHERE merged_table_id IS NOT NULL
    "), 0, 'No published geoskus' or die;
    is scalar $izel->{dbh}->selectall_array("
        SELECT * FROM $Izel::CONFIG->{index_table_name}
    "), 0, 'Removed all index table entries';
    $izel->{dbh}->disconnect;
};

subtest 'map_some_skus' => sub {
    $izel = newTestable();
    is $izel->ingest_sku_from_csv( path => 'data/small.csv'), 18, 'import';

    my $tables = $izel->map_some_skus( skus_text => 'ARTHR, SCSC') or die;
    INFO '-' x 100;
    $table = $tables->[0];
    test_table_obj($table);
    warn Dumper $tables;
    is_deeply ($table->{skus}, ['ARTHR', 'SCSC'], 'skus') or die;
    is $table->{count}, 18, 'count';
    is $table->{name}, "Merged Table #0 (ARTHR - SCSC)", 'name';
    is $table->{index_number}, 0, 'index_number';

    is $izel->is_sku_valid( $table->{skus}->[0] ), 1, 'is_sku_valid' or die;
    is $izel->is_sku_published( $table->{skus}->[0] ), 1, 'is_sku_published' or die;

    INFO '-' x 100;
};

subtest 'get_geoid2s_for_sku' => sub {
    @_ = $table->get_geoid2s_for_sku('ARTHR'),
    is $#_, 14-1, 'Gets ARTHR';
};

done_testing();
exit;


sub newTestable {
    my $wipe = shift;
    $wipe = 1 if not defined $wipe;
    INFO 'Create new Izel, wipe? ', $wipe;
    my $izel = Izel->new(
        recreate_db => $wipe,
        dbname => 'izeltest',
        ua => Test::LWP::UserAgent->new(
            network_fallback => 0
        ),
        output_dir => File::Temp::tempdir( CLEANUP => 1 ),
        auth_string => 'mock_auth_string=keyandaccess_token=mock_access_token',
    );

    isa_ok($izel, 'Izel');
    isa_ok($izel->{ua}, 'LWP::UserAgent');
    isa_ok($izel->{ua}, 'Test::LWP::UserAgent');

    $izel->{ua}->map_response(
        qr{$Izel::CONFIG->{endpoints}->{_create_table_on_google}},
        HTTP::Response->new(
            '200',
            'OK',
            ['content-type' => 'application/json'],
            JSON::Any->objToJson(
                $MOCK_RES_CONTENT->{_create_table_on_google}
            )
        )
    );

    $izel->{ua}->map_response(
        qr{$Izel::CONFIG->{endpoints}->{gsql}},
        HTTP::Response->new(
            '200',
            'OK',
            ['Content-Type' => 'application/json'],
            JSON::Any->objToJson(
                $MOCK_RES_CONTENT->{gsql}
            )
        )
    );

    $izel->{ua}->map_response(
        sub {
            warn 'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';
            my $request = shift;
            # return 1 if $request->method eq 'GET' || $request->method eq 'POST';
            die Dumper $request;
        },
        HTTP::Response->new('200'),
    );

    return $izel;
}

sub test_data_in_db {
    my $izel = shift;
    my $set = $izel->{dbh}->selectall_arrayref("
        SELECT DISTINCT sku FROM $Izel::CONFIG->{geosku_table_name}
    ");
    isnt scalar @$set, 0, 'Found commited geoskus' or LOGCONFESS;
    is scalar @$set, 2, '18 FT refs in index geosku name' or LOGCONFESS 'Expected commited geoskus';

    $set = $izel->{dbh}->selectall_arrayref("
        SELECT * FROM $Izel::CONFIG->{index_table_name}
    ");
    return is scalar @$set, 1, 'One FT ref  index geosku name' or die 'Expected commited geoskus';
}

sub test_table_obj {
    foreach my $table (@_) {
        isa_ok $table->{dbh}, 'DBI::db', 'dbh';
        for (qw( auth_string jsoner ua auth_string )) {
            ok exists $table->{$_}, "$_ field";
        }
    }
    return @_;
}

