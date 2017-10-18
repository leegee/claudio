use strict;
use warnings;
use Data::Dumper;
use Test::More;
use Test::Exception;

use lib 'lib';
use Izel;

my $izel = Izel->new;
isa_ok($izel, 'Izel');

subtest 'DB init' => sub {
    unlink $Izel::CONFIG->{db_path} if -e $Izel::CONFIG->{db_path};

    lives_ok { $izel->get_dbh } 'Got DBH';
    ok $izel->{dbh}, 'DBH';
    ok -e $Izel::CONFIG->{db_path}, 'DB file created';
    my $stat = join('',  stat $Izel::CONFIG->{db_path});

    lives_ok { $izel->get_dbh } 'Got DBH';
    is $stat, join('',  stat $Izel::CONFIG->{db_path}), 'Did not overwrite existing db';
};

is $izel->load_geo_sku_from_csv( path => 'data/small.csv'), 18, 'import';

is_deeply $izel->get_initials(), ['A', 'S'], 'Initials';

subtest 'get_dir_from_path' => sub {
    is $izel->get_dir_from_path('/foo/bar/baz.ext'), '/foo/bar/baz', 'get_dir_from_path with filename';
    is $izel->get_dir_from_path('/foo/bar/baz'), '/foo/bar/baz', 'get_dir_from_path with path';
};


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
}, 'distribute_for_fusion_tables';

done_testing();
