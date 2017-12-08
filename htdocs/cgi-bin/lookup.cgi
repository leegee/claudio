#!/usr/bin/perl
use strict;
use warnings;
use DBI;

my $sku = $ENV{QUERY_STRING};

print "Content-type: text/plain\n\n";

# my $dsn = "dbi:SQLite:dbname=$CONFIG->{db_path}"; my $user = ''; my $pass = '';
my $user = $ENV{IZEL_MAPS_DB_USER} || 'izelplan_geosku';
my $pass = $ENV{IZEL_MAPS_DB_PASS} || 'g305ku-p455w0rd';
my $dbname = $ENV{IZEL_MAPS_DB_DBNAME} || 'izelplan_geosku';
my $dsn = "dbi:mysql:dbname=$dbname";

my $dbh = DBI->connect($dsn, $user, $pass)
        or die "Cannot connect to local mysql with $dsn $user:$pass";

my $res = $dbh->selectall_arrayref("
        SELECT DISTINCT table_index.url AS googleTableId,
                geosku.sku AS sku,
                table_index.id AS internalTableId
         FROM geosku
         JOIN table_index
           ON geosku.merged_table_id = table_index.id
        WHERE sku = ?
", {}, $sku);

eval {
        print $res->[0][0];
};
if ($@){
        print $@;
}
print "\n";

exit;
