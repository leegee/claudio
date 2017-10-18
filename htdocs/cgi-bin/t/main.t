use strict;
use warnings;
use Data::Dumper;
use Test::More;
use Test::Exception;

use lib 'lib';
use Izel;

my $izel = Izel->new;
isa_ok($izel, 'Izel');

subtest 'DB scheme init' => sub {
    unlink $Izel::CONFIG->{db_path} if -e $Izel::CONFIG->{db_path};

    lives_ok { $izel->get_dbh } 'get';
    ok $izel->{dbh}, 'exists';
    ok -e $Izel::CONFIG->{db_path}, 'DB file created';
    my $stat = join('',  stat $Izel::CONFIG->{db_path});

    lives_ok { $izel->get_dbh } 'get again';
    is $stat, join('',  stat $Izel::CONFIG->{db_path}), 'Did not overwrite existing db';
};

is $izel->load_geo_sku_from_csv( path => 'data/small.csv'), 18, 'import';

is_deeply $izel->get_initials(), ['A', 'S'], 'Initials';

subtest 'get_dir_from_path' => sub {
    is $izel->get_dir_from_path('/foo/bar/baz.ext'), '/foo/bar/baz', 'with filename';
    is $izel->get_dir_from_path('/foo/bar/baz'), '/foo/bar/baz', 'with path';
};

subtest 'distribute_for_fusion_tables' => sub {
    is_deeply $izel->distribute_for_fusion_tables, {
        'tables' => [
            bless( {
                'skus' => [
                    'ARTHR',
                    'SCSC'
                ],
                'count' => 18
            }, 'Table' )
        ],
        'total' => 18
    }, 'massive limit, tiny data: one table';

    is_deeply $izel->distribute_for_fusion_tables(14), {
        'tables' => [
            bless( {
                'count' => 14,
                'skus' => [
                        'ARTHR'
                    ]
                }, 'Table' ),
            bless( {
                'skus' => [
                        'SCSC'
                    ],
                'count' => 4
            }, 'Table' )
        ],
        'total' => 18
    }, 'force two tables';

};

done_testing();
