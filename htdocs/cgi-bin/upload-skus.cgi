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

eval {
    main();
};

if ($@) {
    print "Content-type: text/plain\n\n", $@;
 }

exit;

sub main {
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
        logging();
        print "content-type:application/json\n\n";
        my $izel = Izel->new(
            auth_string         => $ENV{QUERY_STRING},
        );
        print $izel->status_json();
        $izel->{dbh}->disconnect;
    }

    elsif ($cgi->param('action') eq 'publish'){
        logging();
        print "content-type:application/json\n\n";
        my $izel = Izel->new(
            auth_string  => $ENV{QUERY_STRING},
            table_id     => $cgi->param('tableId')
        );
        $izel->publish_fusion_table();
        $izel->{dbh}->disconnect;
    }

    elsif ($cgi->param('action') eq 'upload-db'){
        real_time_html('INFO');
        INFO "Will upload the file...";
        my $izel = Izel->new(
            auth_string         => $ENV{QUERY_STRING},
        );
        $izel->upload_db(
            skus_file_handle    => $IN,
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'augment-db'){
        real_time_html('INFO');
        INFO "Will upload the file...";
        my $izel = Izel->new(
            auth_string         => $ENV{QUERY_STRING},
        );
        $izel->augment_db(
            skus_file_handle    => $IN,
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'wipe-google-data') {
        real_time_html('DEBUG');
        INFO "Will wipe-google-data";
        my $izel = Izel->new(
            auth_string         => $ENV{QUERY_STRING},
        );
        $izel->wipe_google_tables();
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'map-some-skus') {
        real_time_html('DEBUG');
        INFO "Will map some skus...";
        my $izel = Izel->new(
            auth_string         => $ENV{QUERY_STRING},
        );
        $izel->map_some_skus(
            skus_text           => $cgi->param('skus-text') .'',
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }
    elsif ($cgi->param('action') eq 'preview-db') {
        logging('DEBUG');
        print "Content-type: application/json\n\n";
        my $izel = Izel->new();
        print $izel->preview_db();
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action')) {
        real_time_html();
        LOGDIE 'Unknown Action, ' . $cgi->param('action');
    }
    else {
        real_time_html();
        LOGDIE 'Missing action field';
    }
}


sub real_time_html {
    my $level = shift || 'INFO';
    print "Content-type: text/html\r\n\r\n";
    $|++;
    Log::Log4perl->init(\"
        log4perl.logger = $level, IzelApp, Screen
        log4perl.appender.IzelApp = HtmlRealTime
        log4perl.appender.IzelApp.layout = PatternLayout
        log4perl.appender.IzelApp.layout.ConversionPattern = %d %m %n
        log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.stderr = 1
        log4perl.appender.Screen.layout = PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = %d %M LINE %L - %m %n
    ");
}

sub logging {
    $|++;
    Log::Log4perl->init(\'
        log4perl.logger = DEBUG, Screen
        log4perl.appender.Screen        = Log::Log4perl::Appender::Screen
        log4perl.appender.Screen.stderr = 1
        log4perl.appender.Screen.layout = PatternLayout
        log4perl.appender.Screen.layout.ConversionPattern = %d %M LINE %L - %m %n
    ');
}