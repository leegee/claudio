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

sub test_table_obj {
    foreach my $field (@_) {
        ok exists $field->{output_dir}, 'output_dir field created';
        ok -d $field->{output_dir}, 'output_dir exists';
        for (qw( output_dir auth_string jsoner ua)) {
            ok exists $field->{$_}, "$_ field";
            delete $field->{$_};
        }
    }
    return @_;
}

subtest 'compute_fusion_tables' => sub {
    @_ = @{ $izel->compute_fusion_tables };
    @_ = test_table_obj(@_);

    is_deeply \@_, [
        bless( {
            'skus' => [ 'ARTHR', 'SCSC' ],
            'count' => 18,
            'name' => 'Table #0',
            'index_number' => 0,
        }, 'Table')
    ], 'massive limit, tiny data: one table';

    @_ = @{ $izel->compute_fusion_tables(14) };
    @_ = test_table_obj(@_);
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
    @_ = $izel->get_geoid2s_for_sku('ARTHR'), 
    is $#_, 14-1, 'Gets ARTHR';
    
};

subtest 'foo' => sub {
    my $cb = sub { $izel->get_geoid2s_for_sku(@_) };
    lives_ok { $cb->('ARTHR') } 'get_geoid2s_for_sku curried callback';
};

subtest 'create_fusion_tables' => sub {
    my $tables = $izel->compute_fusion_tables;
    my $path = $tables->[0]->_create_file( sub { $izel->get_geoid2s_for_sku(@_) } );
    ok -e $path, 'Created CSV';

    throws_ok { $tables->[0]->_publish_table_to_google( path => $path ) } qr/Missing fields: auth_string/;
};

done_testing();
