use strict;
use warnings;

use Log::Log4perl ':easy';
Log::Log4perl->easy_init({
    file => 'STDERR',
    level => $TRACE
});


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

sub test_dirs {
    foreach (@_) {
        ok exists $_->{dir}, 'dir field created';
        ok -d $_->{dir}, 'dir exists';
        delete $_->{dir};
    }
    return @_;
}

subtest 'compute_fusion_tables' => sub {
    @_ = @{ $izel->compute_fusion_tables };
    @_ = test_dirs(@_);

    is_deeply \@_, [
        bless( {
            'skus' => [ 'ARTHR', 'SCSC' ],
            'count' => 18,
            'name' => 'Table #0',
            'index_number' => 0,
        }, 'Table')
    ], 'massive limit, tiny data: one table';

    @_ = @{ $izel->compute_fusion_tables(14) };
    @_ = test_dirs(@_);
    is_deeply \@_, [
        bless( {
            'count' => 14,
            'skus' => [ 'ARTHR' ],
            'name' => 'Table #0',
            'index_number' => 0,
            }, 'Table' 
        ),
        bless( {
            'count' => 4,
            'skus' => [ 'SCSC' ],
            'name' => 'Table #1',
            'index_number' => 1,
            }, 'Table' 
        )
    ], 'force two tables';
};

subtest 'get_geoid2s_for_sku' => sub {
    dies_ok { $izel->get_geoid2s_for_sku }, 'Requires SKU';
    @_ = $izel->get_geoid2s_for_sku('ARTHR'), 
    is $#_, 14-1, 'Gets ARTHR';
    
};

subtest 'create_fusion_tables' => sub {
    my $tables = $izel->compute_fusion_tables;
    $tables->[0]->_create_file(
        $izel, $izel->can('get_geoid2s_for_sku')
    );
};

done_testing();
