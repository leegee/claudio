#!perl
use strict;
use warnings;

use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';

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

LOGDIE 'No $ENV{DOCUMENT_ROOT} !!!' if not $ENV{DOCUMENT_ROOT};

my $cgi = CGI->new;
my @missing = grep {! $cgi->param($_) } qw/ skus-file index_js_dir /;
my $IN  = $cgi->upload('skus-file');
push(@missing, '(skus-file is not a filehandle)') if not defined $IN;
if (@missing) {
    return 'Missing params: ', join ', ', @missing;
}

Izel::upload_skus(
    skus_file_handle    => $IN,
    auth_string         => $ENV{QUERY_STRING},
    skus_text           => $cgi->param('skus-text'),
    output_dir          => $ENV{DOCUMENT_ROOT} . $cgi->param('index_js_dir'),
);

exit;


