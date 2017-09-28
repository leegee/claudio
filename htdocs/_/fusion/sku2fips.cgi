#!/usr/bin/env perl
use strict;
use warnings;

use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';
Log::Log4perl->easy_init($TRACE);

require DBI;
require DBD::mysql;

our $Config = {
	make_kmz => 1,
	db => {
		server		=> 'localhost',
		username	=> 'izelplan_geo',
		password	=> 'this-is-the-maps-database',
		name		=> 'izelplan_geo',
	},
	tables => {
		counties	=> 'counties',
		plants		=> 'plants',
	}
};

print "Content-type: application/json\n\n";
my $o = Izel->new;
my $sku = $ENV{PATH_INFO};
if (not defined $sku){
	print '{"error":"No SKU supplied in PATH_INFO"}';
}
else {
	$sku =~ s{/}{};
	my $fips = $o->sku2fips( $sku );
	if (not $fips){
		print '{"error":"No FIPS for supplied SKU, '.$sku.' "}';
	} 
	else {
		print '{ "county_fips": [',
			join(',', 
				map{ s/^0//; "\"$_\"" } @$fips
			),
		']}'
	}
}
exit;

package Izel;
use Log::Log4perl ':easy';

sub new {
	my ($inv, $args) = @_;
	my $self = bless {}, ref($inv)? ref($inv) : $inv;
	$self->{dbh} = $inv->connect();
	$self->{res} = undef;
	return $self;
}

sub connect {
	TRACE "DB CX ".$Config->{db}->{name};
	my $dbh = DBI->connect(
		"DBI:mysql:database=" . $Config->{db}->{name},
		$Config->{db}->{username},
		$Config->{db}->{password}
	);
	$dbh->{'mysql_enable_utf8'} = 1;
	return $dbh;
}

sub sku2fips {
	my ($self, $sku) = @_;
	my $sql = 'SELECT DISTINCT county_fips FROM '
		. $Config->{tables}->{plants}
		. ' WHERE sku=? LIMIT 9999';
	TRACE $sql, ' ', $sku;
	return $self->{dbh}->selectcol_arrayref(
		$sql,
		{},
		$sku
	);
}

1;
