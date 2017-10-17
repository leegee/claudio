use strict;
use warnings;

#
# Not an ideal DB - not linked to Magento,
# and no links due to geospatial being only in MyISAM
# and lots of repition, but optimal for searching.
#

package Izel;

use LWP::UserAgent();
use Encode;
use Log::Log4perl ':easy';
use Text::CSV_XS;

use JSON::Any;
my $Jsoner = JSON::Any->new;
my $UA;

# The CSV is the list of SKUs that are in stock
sub skus_from_csv {
	TRACE "Enter";
	my $no_paths = shift || 0;
	my $path = shift;
	die 'No path?' if not $path;

	require Text::CSV_XS;
	my @skus;
	my $csv = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
	open my $fh, "<:encoding(utf8)", $path
		or LOGDIE "$path - $!";
	while (my $row = $csv->getline ($fh)) {
		my $sku = $row->[0];
		$sku =~ s/^\s+//;
		$sku =~ s/\s+$//;
		push @skus, $no_paths?
			$sku : join'/',Izel->_path_bits( $sku );
	}
	close $fh;
	TRACE "Read ", scalar(@skus), " skus";

	return @skus;
}

=head2 create_fusion_csv_multiple

Creates multiple CSVs and a JSON index of which SKU is in
which CSV, because Fusion Tables only imports small CSVs at
the time of writing.

Accepts C<sku2latin_path>, C<county_distributions_path>,
C<output_path>, and C<number_of_output_files>.

The former is a CSV of SKU,Latin Name.

The latter is a bar-delimited list of SKU|FIPS, one per line:

	SCSC|53007

Also accepts C<include_only_skus>, an array of SKUs to include - all others in the csv will be dropped.

=cut

sub create_fusion_csv_multiple {
	TRACE "Enter";
	my $args = ref($_[0])? shift : {@_};
    $args->{number_of_output_files} ||= 5;

	my $fh_index = -1;
	my $rows_done = 0;
	my $az = {};

	my $res = {
		skus2tableIndex => {},
		csvs => [],
		fusiontables => [],
		# rows_done => 0,
		# az => {}
	};

    my $skus = load_sku2latin_from_csv($args);

	open my $IN, "<:encoding(utf8)", $args->{county_distributions_path}
		or LOGDIE "$! - $args->{county_distributions_path}";

	my $csv_bar = Text::CSV_XS->new({
		sep_char 	=> '|',
		binary 		=> 1,
		auto_diag 	=> 1
	});

	while (my $row = $csv_bar->getline($IN)) {
		my $sku  = uc $row->[0];
		my $fips = $row->[1];
		my ($state_num, $county_num) = $fips =~ (/^(\d{1,2})(\d{3})$/);
		my $geo_id2 = $fips + 0;
		# TRACE $geo_id2.'...'.$fips, "\n";
		if (exists $skus->{$sku}){
			++ $rows_done;
			my $initial = substr $sku,0,1;
			push @{$az->{$initial}->{$sku}}, $geo_id2;
		}
	}
	close $IN;

	my $csv_comma = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
    $csv_comma->eol("\n");

	my @keys = sort {
		scalar keys %{$az->{$b}}
			<=>
		scalar keys %{$az->{$a}}
	} keys %$az;

	# Distribute volumes of SKUs across multiple files.
	# Order output by volume.
	# Write alternatly to one of several outupt files
	my ($dir, $ext) = $args->{output_path} =~ /^(.+?)(\.[^.]+)?$/;
	$res->{dir} = $dir;
	mkdir $dir or die "$! - $dir";
	
	my (@OUT, $fh);

	for my $i (0 .. $args->{number_of_output_files} -1){
		my $pathCsv = $dir .'/'. $i . '.csv';
		push @{$res->{csvs}}, $pathCsv;
		my $name = 'table_' . $i;

		publish_table_to_google({
			name => $name,
			auth_string => $args->{auth_string},
			table => {
				name => $name,
				isExportable => 'true',
				description => 'Table ' . $i,
				columns => [ 
					{
						name => "GEO_ID2",
						type => "STRING",
						kind => "fusiontables#column",
						columnId => 1
					},
					{
						name => "SKU",
						type => "STRING",
						kind => "fusiontables#column",
						columnId => 2
					},
				]
			}
		});
		
		open $fh, ">:encoding(utf8)", $pathCsv or die "$! - $pathCsv";
		push @OUT, $fh;
		print $fh "GEO_ID2,SKU\n";
	}

	while (@keys){
		$fh_index ++;
		$fh_index = 0 if $fh_index >= $args->{number_of_output_files};
		my $initial = shift @keys;
		INFO sprintf "SKUs initial %s with %s into %s",
			$initial, scalar( keys %{ $az->{$initial} }), $fh_index;

		foreach my $sku (sort keys %{ $az->{$initial} }){
			$res->{skus2tableIndex}->{$sku} = $fh_index;

			foreach my $geo_id2 (@{
				$az->{$initial}->{$sku}
			} ){
				$csv_comma->print( $OUT[$fh_index], [
					$geo_id2, $sku
				]);
			}
		}

		# Terminate JSON
		print $fh "]\n";
	}

	close $_ foreach @OUT;

	INFO "Create $dir/index.js";
	open $fh, ">:encoding(utf8)", "$dir/index.js" or die "$! - $dir/index.js";
	my $jsonRes = $Jsoner->encode( $res );
	print $fh $jsonRes;
	close $fh;

	# return $rows_done, $az, $skus2tableIndex;
	return $jsonRes;
}


sub publish_table_to_google {
    TRACE "Enter";
    my $args = ref($_[0])? shift : {@_};
    my $body = $Jsoner->encode($args);

	if (!$UA){
		$UA = LWP::UserAgent->new;
		$UA->timeout(30);
		$UA->env_proxy;
	}

    my $url = 'https://www.googleapis.com/fusiontables/v2/tables'
		. '?uploadType=media'
		. '&name=' . $args->{name}
		. '&' . $args->{auth_string},

	my $response = $UA->post(
		'http://search.cpan.org/', 
		Content => $Jsoner->encode($args->{table})
	);

	if ($response->is_success) {
		print $response->decoded_content;  # or whatever
	}
	else {
		die $response->status_line;
	}
}

=head2 (METHOD) create_fusion_csv

As create_fusion_csv_multiple but creates one file.

Also accepts C<log>, which if present ought to be a filehandle (ie STDOUT).

=cut

sub create_fusion_csv {
    TRACE "Enter";
    my $args = ref($_[0])? shift : {@_};

    $args->{log}->print("Opening county distribution file, $args->{county_distributions_path}") if $args->{log};

    open my $IN, "<:encoding(utf8)", $args->{county_distributions_path}
        or LOGDIE "$! - $args->{county_distributions_path}";

    my $rows_done = 0;
    my $skus = {};

    my $csv_bar = Text::CSV_XS->new({
        sep_char    => '|',
        binary      => 1,
        auto_diag   => 1
    });

    while (my $row = $csv_bar->getline($IN)) {
        my $sku  = uc $row->[0];
        my $fips = $row->[1];
        my ($state_num, $county_num) = $fips =~ (/^(\d{1,2})(\d{3})$/);
        my $geo_id2 = $fips + 0;
        # DEBUG 'FIPS '.$fips. ' = GEO_ID2 '.$geo_id2;
        ++ $rows_done;
        push @{$skus->{$sku}}, $geo_id2;
        $args->{log}->print("Read $sku $geo_id2") if $args->{log};
    }
    close $IN;

    my $csv_comma = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
    $csv_comma->eol ("\n");

    my ($dir, $ext) = $args->{output_path} =~ /^(.+?)(\.[^.]+)?$/;
	$dir ||= '';
    if ($dir && !-d $dir) {
        mkdir $dir or die "$! - $dir";
    }
    
    my @OUT;
    my $path = $dir .'/sku2geoid2' . '.csv';
    open my $fh, ">:encoding(utf8)", $path or die "$! - $path";
    $args->{log}->print("Writing $path") if $args->{log};

    my $skus_done = 0;
    foreach my $sku (sort keys %$skus ){
        ++ $skus_done;
        foreach my $geo_id2 (@{$skus->{$sku}} ){
            $csv_comma->print(
                $fh,
                [ $geo_id2, $sku ]
            );
        }
        $args->{log}->print("Wrote $skus_done SKUs") if $args->{log} and $skus_done % 100 == 1;
    }

    close $fh;

    $args->{log}->print("Wrote a total of $skus_done SKUs") if $args->{log};

    return $rows_done, $skus_done, $path;
}


sub load_sku2latin_from_csv {
    my $args = shift;
    my $skus = {};
    my $csv_comma = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
    INFO "Reading ",$args->{sku2latin_path};
    open my $IN, "<:encoding(utf8)", $args->{sku2latin_path}
        or LOGDIE "$! - $args->{sku2latin_path}";
    while (my $row = $csv_comma->getline($IN)) {
        my $sku = uc $row->[0];
        $sku =~ s/^\s+//;
        $sku =~ s/\s+$//;
        $skus->{$sku} = $row->[1] || 1;
        DEBUG "$sku = $skus->{$sku}";
    }
    close $IN;
    TRACE "Read ", scalar keys(%$skus), " skus";
    return $skus;
}



1;
