#!perl
use strict;
use warnings;

# use utf8::all;
use IO::Handle;
use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';
use Data::Dumper;

use lib 'lib';
use Izel;

Log::Log4perl->easy_init({
    file => 'C:/Users/User/src/izel/htdocs/cgi.log',
    level => DEBUG
});

TRACE 'Init';

$CGI::POST_MAX = 1024 * 10000;
$CGI::DISABLE_UPLOADS = 0; 
$| = 1;

my $sku_csv     = 'latest_skus.csv';
my $counties	= 'data/county_distrib_11-19-09.txt';

my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
my $merged_geo_skus_dir = sprintf "temp/skus_%d%02d%02d-%02d%02d%02d/", $year+1900, $mon+1, $mday, $hour, $min, $sec;

main();
exit;

sub main {
    my $cgi = CGI->new;
    my $IN  = $cgi->upload('skus-csv');
    if (! defined $IN) {
        die 'Missing file field, "skus-csv"';
    }
    binmode $IN;

    TRACE 'Write uploaded skus to ', $sku_csv;
    open my $OUT,">:utf8", $sku_csv or LOGDIE "$! - $sku_csv";
    my $io_handle = $IN->handle;
    binmode $io_handle;
    while (my $bytesread = $io_handle->read(my $buffer,1024)) {
        print $OUT $buffer;
    }

    close $OUT;
    close $IN;
    TRACE 'Finished writing uploaded skus to file';
    
# my ($row_count, $skus_count, $path) = Izel::Init::create_fusion_csv_multiple(
# 	county_distributions_path => $counties,
# 	stock_skus_path => $sku,
# 	output_path		=> $output,
#     number_of_output_files => $number_of_output_files,
# );

    TRACE 'Call create_fusion_csv_multiple';
    my $jsonRes = Izel::create_fusion_csv_multiple(
        county_distributions_path   => $counties,
        stock_skus_path             => $sku_csv,
        output_path	    	        => $merged_geo_skus_dir,
    );
    TRACE 'Done  create_fusion_csv_multiple';

    warn Dumper $jsonRes;

    # TRACE 'Reading merged_path, ', $merged_path;
    # open $IN, $merged_path or die "$! - $merged_path";
    # binmode $IN;
    # local $/ = \2048;
    # while (<$IN>) {
    #     print $_;
    # }
    # close $IN;

    # select()->flush();

    # print "Content-type: application/json\r\n\r\n{\"path\":\"$merged_path\"}\n\r";
    print "Content-type: application/json\r\n\r\n", $jsonRes;
}
