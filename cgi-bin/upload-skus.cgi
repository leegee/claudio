#!perl

use strict;
use warnings;

use lib 'lib';
use Izel;

# use utf8::all;
use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';
use Data::Dumper;

Log::Log4perl->easy_init( $DEBUG );
$CGI::POST_MAX = 1024 * 10000;
$CGI::DISABLE_UPLOADS = 0; 
$| = 1;

my $sku_csv     = 'latest_skus.csv';
my $counties	= 'data/county_distrib_11-19-09.txt';

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
my $merged_geo_skus_path = sprintf "temp/skus_%d%02d%02d-%02d%02d%02d/", $year+1900, $mon+1, $mday, $hour, $min, $sec;

main();
exit;

sub main {
    my $cgi = CGI->new;
    my $IN  = $cgi->upload('skus-csv');
    if (! defined $IN) {
        die 'No FH for upload, ' . $cgi->param('skus-csv');
    }
    binmode $IN;

    open my $OUT,">:utf8", $sku_csv or die "$! - $sku_csv";
 
    my $io_handle = $IN->handle;
    binmode $io_handle;
    while (my $bytesread = $io_handle->read(my $buffer,1024)) {
        INFO $OUT;
        print $OUT $buffer;
    }

    close $OUT;
    close $IN;
    
    my ($rows_done, $skus_done, $path) = Izel::create_fusion_csv(
        county_distributions_path   => $counties,
        stock_skus_path             => $sku_csv,
        output_path	    	        => $merged_geo_skus_path,
    );

    #     Dumper($skus_done), "\n\r",
    #     Dumper($path), "\n\r";

    # open my $IN, $merged_geo_skus_path or die "$! - $merged_geo_skus_path";
    # binmode $IN;
    # local $/ = \2048;
    # while (<$IN>) {
    #     print $_;
    # }
    # close $IN;

    print "Content-type: application/json\r\n\r\n{path:\"$merged_geo_skus_path\"}\n\r";
}
