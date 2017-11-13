#!perl
use strict;
use warnings;

use CGI;
use CGI::Carp 'fatalsToBrowser';
use Log::Log4perl ':easy';

use lib 'lib';
use Izel;

my $SERVICE_AC_ID = 'izel-dev@izel-maps-dev.iam.gserviceaccount.com';

my $PRIVATE_KEY = << '_END_OF_KEY_';
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCQoh0VwKyOqHQA
o36KwAuhvSABnRcLRBw0qho4/QVwp2wfqbJO+u/YD5xlkeiqa9OusJmkGxlW7c8u
eJaSrPSaGXgrZYwm0aqJu310wamB73hgD7z67z+09sVzhCKr2+ULEgoWgb74ZAE4
1ny+toF9S/BAT240+f1aBVyXYFcPiYEbo80PrQmhDFZ2yc/Hh1cCvRH10rsF56rY
7CIGvgaZldBdpWKzQllod4Ccm8XdpSqYQ0PNjP/P6snddKdwjYYeK5FOxjKTVq+1
nS7g5iMzgCZoctN+a/HAMt4/mkA6lGSpRyCdWwNc+a+IsUdye4b2IAqG2VlpZ6Sv
/UZRFsR/AgMBAAECggEADl/mVx6ep9ELMnMNZRngLhN/ZlmoDCkZSoyrbYWMMF2b
a+wwOhRLmSQ4DYo6XxG3aLHJm1tMIe0hvcMjZ/GDn/svC9UcYFFPS0AUoHGM+MqF
orp9tEzp/oDWL/xue7kvovGIiiMcCVDbJDyBCm1WIk9VUfbzA5Xi/brxsGPVU0hX
iKMJGuKEPlvkgN0nHeWxlOZ3jlXrh3ZoyMaKxCCH2PyEOFH+eIK7eWCd5Rri2/5e
aB3gBxkxSd7nu1Qrv8E1cMWkQ10ORVj+RQaM9A705lVEdNHL/lMV1ik0iETCisjU
kYoNhpveWtfy2u/7KSKfk3dD6ClGofCfYCvYjrXpWQKBgQDEGMB1fhTxB3Ja4tEl
cDD5nQeQ3a4TJLvgwNdCyDHeuBxsF/TJs8CDJSk6V6JGjGFgw4cUSXgpywXbNqXt
qG9LVmp9baZZeCjyL5af4nQ2edYr44IrtdSQ0OTNzB3IBcMOSav8OlkkTHmEL2qn
jkS9S0pvnnotnHtwQiGE6wQ5lwKBgQC80MsuTcCcx+UirKXBql9TpX7vDVr/Wl0+
Fu3NoUPR04HfflYweLqweAHq8LKsvJyoB++Rjuuck0gH2vJe1mgIbxVcjOe83uq0
WHX7vbJnJIWwyJIPes7ADtgMqM8SfQq+xG7dYSoKWS36nhUKPaMFFwWoc1H+OF30
c7Sy7tkZWQKBgCgP2nnmeUbIu68fuZTJd+f3Ec2hzGdy0MNZAmFNXwreWEgpGMSA
aashU2vs7WU2VsqbB6S4YclABgFEB+Am0h31GKppVVvf9ZWM7Vvaut1KRNwQjc56
RmQTmTsGIWt06eWoXW+ZSA7nZMgBm+uBYD+/+wQUv2dEGd/UUt7B2MofAoGAKbTE
7HloLjlJN5uDEYAchlFr9Emy6+x95BUUefNBE7vwV/mD+Djyo8AeTFLWZKlUwRjf
pfs3t+IgavvFxYT+fb5rrYHCPknO9f8EMJL6MSY0EZR8DsdFm86rkkBHXQIZuYGS
K3wm2RpRuaXpZ9WtiJZJPagbWFgDCNf19gAkHCECgYEAsB9J9km9q96jbXDzcjSV
/0i9LKnzkv87jkYDYtDo5Jt/C/hscFMs8Fb17/vi74rMHg5gDfgQ7I3rYa8+Ro9q
E4Bd1YXmac02PamJfxkTU0bhJDJz4I48c4R+/ELEWhUWgael8StGZ0NJzOcrmdpm
gujIxSvMW3VyKC5+uj3bUEo=
-----END PRIVATE KEY-----
_END_OF_KEY_

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
    if ($cgi->param('action') =~ /^(augment|upload)-db$/){
        my @missing = grep {! $cgi->param($_) } qw/ skus-file action /;
        $IN  = $cgi->upload('skus-file');
        push(@missing, '(skus-file is not a filehandle)') if not defined $IN;
        LOGDIE 'Missing params: ' . join(', ', @missing) if @missing;
    }

    my $param = {
        private_key => $PRIVATE_KEY,
        service_ac_id => $SERVICE_AC_ID,
        id_token => $cgi->param('id_token'),
        client_id => $cgi->param('client_id'),
    };

    my @missing = grep {! $cgi->param($_) } qw/ id_token client_id /;
    LOGDIE 'Missing auth params: ' . join(', ', @missing) if @missing;

    if ($cgi->param('action') eq 'status'){
        logging();
        print "content-type:application/json\n\n";
        my $izel = Izel->new($param);
        print $izel->status_json();
        $izel->{dbh}->disconnect;
    }

    elsif ($cgi->param('action') eq 'publish'){
        logging();
        print "content-type:application/json\n\n";
        my $izel = Izel->new($param);
        $izel->publish_json(
            tableId            => $cgi->param('tableId')
        );
        $izel->{dbh}->disconnect;
    }

    elsif ($cgi->param('action') eq 'upload-db'){
        real_time_html('INFO');
        INFO "Will upload the file...";
        my $izel = Izel->new($param);
        $izel->upload_db(
            skus_file_handle    => $IN,
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'augment-db'){
        real_time_html('INFO');
        INFO "Will upload the file...";
        my $izel = Izel->new($param);
        $izel->augment_db(
            skus_file_handle    => $IN,
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'wipe-google-data') {
        real_time_html('DEBUG');
        INFO "Will wipe-google-data";
        my $izel = Izel->new($param);
        $izel->wipe_google_tables();
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }

    elsif ($cgi->param('action') eq 'map-some-skus') {
        real_time_html('DEBUG');
        INFO "Will map some skus...";
        my $izel = Izel->new($param);
        $izel->map_some_skus(
            skus_text           => $cgi->param('skus-text') .'',
        );
        $izel->{dbh}->disconnect;
        INFO "Finished - you can now leave this screen";
    }
    elsif ($cgi->param('action') eq 'preview-db') {
        logging('DEBUG');
        print "Content-type: application/json\n\n";
        my $izel = Izel->new($param);
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