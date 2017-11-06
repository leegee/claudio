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
die 'No $ENV{QUERY_STRING}' if not $ENV{QUERY_STRING};

my $IN;
my $cgi = CGI->new;
my @missing = grep {! $cgi->param($_) } qw/ skus-file action /;

if ($cgi->param('action') =~ /^(augment|upload)-db$/){
    $IN  = $cgi->upload('skus-file');
    push(@missing, '(skus-file is not a filehandle)') if not defined $IN;
    if (@missing) {
        LOGDIE 'Missing params: ', join ', ', @missing;
    }
}

if ($cgi->param('action') eq 'status'){
    print "content-type:application/json\n\n";
    print Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->status_json();
}

elsif ($cgi->param('action') eq 'upload-db'){
    real_time_html();
    INFO "Will upload the file...";
    Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->upload_db(
        skus_file_handle    => $IN,
    );
}

elsif ($cgi->param('action') eq 'augment-db'){
    real_time_html();
    INFO "Will upload the file...";
    Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->augment_db(
        skus_file_handle    => $IN,
    );
}

elsif ($cgi->param('action') eq 'publish-some-skus') {
    real_time_html();
    INFO "Will publish some skus...";
    Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->process_some_skus(
        skus_text           => $cgi->param('skus-text') .'',
    );
}

elsif ($cgi->param('action') eq 'resume-previous') {
    real_time_html();
    INFO "Will resume the previous upload...";
    Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->resume_previous();
}

elsif ($cgi->param('action') eq 'restart-previous') {
    real_time_html();
    INFO "Will restart the previous upload...";
    Izel->new(
        auth_string         => $ENV{QUERY_STRING},
    )->restart_previous();
}

elsif ($cgi->param('action') eq 'previewDb') {
    print "Content-type: application/json\n\n",
        Izel->new()->preview_db();
}

elsif ($cgi->param('action')) {
    real_time_html();
    LOGDIE 'Unknown Action, ' . $cgi->param('action');
}
else {
    real_time_html();
    LOGDIE 'Missing action field';
}

exit;


sub real_time_html {
    print "Content-type: text/html\r\n\r\n";
    $|++;
    Log::Log4perl->init(\'
        log4perl.logger = TRACE, IzelApp, Screen
        log4perl.appender.IzelApp = HtmlRealTime
        log4perl.appender.IzelApp.layout = PatternLayout
        log4perl.appender.IzelApp.layout.ConversionPattern = %d %m %n
        log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.stderr = 1
        log4perl.appender.Screen.layout = PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = %d %M LINE %L - %m %n
    ');
}