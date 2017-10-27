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
use Test::LWP::UserAgent;
use File::Temp;
use JSON::Any;
use lib 'lib';
use Izel;

my $izel = Izel->new(
    ua => Test::LWP::UserAgent->new(
        network_fallback => 0
    ),
    output_dir => File::Temp::tempdir( CLEANUP => 1 ),
    auth_string => 'mock',
);
isa_ok($izel, 'Izel');

my $MOCK_RES_CONTENT = {
    _create_table_on_google => {tableId => 'MOCK_TABLE_ID'},
    gsql => {rows => [[999]]}
};

$izel->{ua}->map_response(
    qr{$Izel::CONFIG->{endpoints}->{_create_table_on_google}},
    HTTP::Response->new(
        '200',
        'OK',
        ['Content-Type' => 'application/json'],
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

$izel->{ua}->map_response(sub {
        my $request = shift;
        # return 1 if $request->method eq 'GET' || $request->method eq 'POST';
        die Dumper $request;
    },
    HTTP::Response->new('200'),
);

subtest 'DB scheme init' => sub {
    unlink $Izel::CONFIG->{db_path} if -e $Izel::CONFIG->{db_path};

    lives_ok { $izel->get_dbh } 'get';
    ok $izel->{dbh}, 'exists';
    ok -e $Izel::CONFIG->{db_path}, 'DB file created';
};

is $izel->load_geo_sku_from_csv( path => 'data/small.csv'), 18, 'import';

is_deeply $izel->get_initials(), ['A', 'S'], 'Initials';

subtest 'get_dir_from_path' => sub {
    is $izel->get_dir_from_path('/foo/bar/baz.ext'), '/foo/bar/baz', 'with filename';
    is $izel->get_dir_from_path('/foo/bar/baz'), '/foo/bar/baz', 'with path';
};

sub test_table_obj {
    foreach my $table (@_) {
        isa_ok $table->{dbh}, 'DBI::db', 'dbh';
        ok exists $table->{output_dir}, 'output_dir field created';
        ok -d $table->{output_dir}, 'output_dir exists';
        for (qw( output_dir auth_string jsoner ua auth_string )) {
            ok exists $table->{$_}, "$_ field";
        }
    }
    return @_;
}

subtest 'compute_fusion_tables' => sub {
    subtest 'massive limit, tiny data: one table' => sub {
        @_ = @{ $izel->compute_fusion_tables };
        @_ = test_table_obj(@_);
        is_deeply $_[0]->{skus}, ['ARTHR', 'SCSC'], 'skus';
        is $_[0]->{count}, 18, 'count';
        is $_[0]->{name}, 'Table #0', 'name';
        is $_[0]->{index_number}, 0, 'index_number';
    };

    subtest 'force two tables' => sub {
        @_ = @{ $izel->compute_fusion_tables(14) };
        @_ = test_table_obj(@_);
        is_deeply $_[0]->{skus}, ['ARTHR'], 'skus';
        is $_[0]->{count}, 14, 'count';
        is $_[0]->{name}, 'Table #0', 'name';
        is $_[0]->{index_number}, 0, 'index_number';

        is_deeply $_[1]->{skus}, ['SCSC'], 'skus';
        is $_[1]->{count}, 4, 'count';
        is $_[1]->{name}, 'Table #1', 'name';
        is $_[1]->{index_number}, 1, 'index_number';
    };
};

# subtest 'get_geoid2s_for_sku' => sub {
#     @_ = $izel->get_geoid2s_for_sku('ARTHR'),
#     is $#_, 14-1, 'Gets ARTHR';

# };

# subtest 'foo' => sub {
#     my $cb = sub { $izel->get_geoid2s_for_sku(@_) };
#     lives_ok { $cb->('ARTHR') } 'get_geoid2s_for_sku curried callback';
# };

subtest 'create_fusion_tables' => sub {
    my $tables = $izel->compute_fusion_tables;
    isa_ok $tables, 'ARRAY', 'rv';

	my @res;
    subtest 'Table::create' => sub {
        foreach my $table (@$tables) {
            isa_ok $table, 'Izel::Table';
            push @res, $table->create();
        }
    };

    subtest 'json index' => sub {
        my $json = JSON::Any->jsonToObj( $izel->_compose_index_file(@res) );
        is_deeply $json, {
            skus2tableIds => {
                ARTHR => '999',
                SCSC => '999'
            },
            mergedTableIds => [ 1 ]
        }, 'json index';

    };

};


done_testing();





