use strict;
use warnings;

use Test::More;
use Test::Exception;

use lib 'lib';
use Izel;

my $izel = Izel->new;
isa_ok($izel, 'Izel');

subtest 'DB init' => sub {
    plan tests => 5;
    unlink $Izel::CONFIG->{db_path} if -e $Izel::CONFIG->{db_path};

    lives_ok { $izel->get_dbh } 'Got DBH';
    ok $izel->{dbh}, 'DBH';
    ok -e $Izel::CONFIG->{db_path}, 'DB file created';
    my $stat = join('',  stat $Izel::CONFIG->{db_path});

    lives_ok { $izel->get_dbh } 'Got DBH';
    is $stat, join('',  stat $Izel::CONFIG->{db_path}), 'Did not overwrite existing db';
};

done_testing();
