#!perl
use strict;
use warnings;

use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';

use lib 'lib';
use Izel;


# Log::Log4perl->easy_init({
#     # file => 'cgi.log',
#     file => {'STDOUT'},
#     level => $TRACE,
#     layout => '%m %l\n'
# });

$CGI::POST_MAX = 1024 * 100000000; # 208795632
$CGI::DISABLE_UPLOADS = 0;

die 'No $ENV{DOCUMENT_ROOT} !!!' if not $ENV{DOCUMENT_ROOT};

my $IN;
my $cgi = CGI->new;
my @missing = grep {! $cgi->param($_) } qw/ skus-file index_js_dir action /;

if ($cgi->param('action') eq 'upload-skus'){
    $IN  = $cgi->upload('skus-file');
    push(@missing, '(skus-file is not a filehandle)') if not defined $IN;
    if (@missing) {
        LOGDIE 'Missing params: ', join ', ', @missing;
    }
}

# resume-previous

if ($cgi->param('action') eq 'upload-skus'){
    print "Content-type: text/html\r\n\r\n";
    $|++;
    Log::Log4perl->init(\'
        log4perl.logger = INFO, IzelApp
        log4perl.appender.IzelApp = HtmlRealTime
        log4perl.appender.IzelApp.layout = PatternLayout
        log4perl.appender.IzelApp.layout.ConversionPattern = %d %m %n
    ');
    INFO "Will upload the file...";
    Izel::upload_skus(
        recreate_db         => $cgi->param('recreate_db'),
        skus_file_handle    => $IN,
        auth_string         => $ENV{QUERY_STRING},
        skus_text           => $cgi->param('skus-text'),
        output_dir          => $ENV{DOCUMENT_ROOT} .'/'. $cgi->param('index_js_dir') .'/',
    );
}

elsif ($cgi->param('action') eq 'resume-previous') {
    print "Content-type: text/html\r\n\r\n";
    Log::Log4perl->easy_init($TRACE);
    INFO "Will resume the previous upload...";
    Izel->new(
        output_dir          => $ENV{DOCUMENT_ROOT} .'/'. $cgi->param('index_js_dir') .'/',
        auth_string         => $ENV{QUERY_STRING},
    )->resume_previous();
}

elsif ($cgi->param('action') eq 'restart-previous') {
    print "Content-type: text/html\r\n\r\n";
    Log::Log4perl->easy_init($TRACE);
    INFO "Will restart the previous upload...";
    Izel->new(
        output_dir          => $ENV{DOCUMENT_ROOT} .'/'. $cgi->param('index_js_dir') .'/',
        auth_string         => $ENV{QUERY_STRING},
    )->restart_previous();
}

elsif ($cgi->param('action') eq 'previewDb') {
    print "Content-type: application/json\n\n",
        Izel->new()->preview_db();
}

elsif ($cgi->param('action')) {
    die 'Unknown Action, ' . $cgi->param('action');
}
else {
    die 'Missing action field';
}

exit;


