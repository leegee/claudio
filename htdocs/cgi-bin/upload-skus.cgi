#!perl
use strict;
use warnings;

package main;

use IO::Handle;
use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';
use Data::Dumper;

use lib 'lib';
use Izel;

print "Content-type: application/json\r\n\r\n";
$|++;

# Log::Log4perl->easy_init({
#     # file => 'cgi.log',
#     file => {'STDOUT'},
#     level => $TRACE,
#     layout => '%m %l\n'
# });

Log::Log4perl->init(\'
    log4perl.logger = TRACE, IzelApp
    log4perl.appender.IzelApp = HtmlRealTime
    log4perl.appender.IzelApp.layout = PatternLayout
    log4perl.appender.IzelApp.layout.ConversionPattern = %d %m %n
');

$CGI::POST_MAX = 1024 * 10000;
$CGI::DISABLE_UPLOADS = 0; 

my $UPLOADED_SKU_CSV = 'latest_skus.csv';

LOGDIE 'No $ENV{DOCUMENT_ROOT}' if not $ENV{DOCUMENT_ROOT};

my @final = main();
print join @final, "\n", "\n\r\n\r";
exit;

sub main {
    my $cgi = CGI->new;

    my @missing = grep {! $cgi->param($_) } qw/ skus-file index_js_dir /;

    my $IN  = $cgi->upload('skus-file');

    if (! defined $IN) {
        push @missing, 'skus-file';
    }
    if (@missing) {
        return 'Missing params: ', join ', ', @missing;
    }

    binmode $IN;

    TRACE 'Process skus' . ($cgi->param('skus-text') || '');
    TRACE 'Write uploaded skus to ', $UPLOADED_SKU_CSV;

    open my $OUT,">:utf8", $UPLOADED_SKU_CSV or LOGDIE "$! - $UPLOADED_SKU_CSV";
    my $io_handle = $IN->handle;
    binmode $io_handle;
    while (my $bytesread = $io_handle->read(my $buffer,1024)) {
        print $OUT $buffer;
    }

    close $OUT;
    close $IN;
    TRACE 'Finished writing uploaded skus to file';
    
    TRACE 'Call create_fusion_csv_multiple';
    my $skus = $cgi->param('skus-text')? [$cgi->param('skus-text').split(/[,\W]+/)] : [];
    
    my $jsonRes = Izel->new(
        auth_string          => $ENV{QUERY_STRING},
    )->create(
        skus2fips_csv_path   => $UPLOADED_SKU_CSV,
        output_dir	    	 => $ENV{DOCUMENT_ROOT} . $cgi->param('index_js_dir'),
        include_only_skus    => $skus
    );

    return $jsonRes;

    TRACE 'Done  create_fusion_csv_multiple';
}

