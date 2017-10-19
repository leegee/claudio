use strict;
use warnings;

package IzelBase;
use Data::Dumper;
use Log::Log4perl ':easy';

sub require_defined_fields {
	my ($self, @fields) = @_;
	my @missing = grep {
		not (exists $self->{$_} || defined $self->{$_}) 
	} @fields;
	LOGCONFESS 'Missing fields: ' . join(', ', @missing) . "\nin " . Dumper($self) if @missing;
}

package Izel;
use base 'IzelBase';
use File::Temp ();
use Data::Dumper;
use LWP::UserAgent();
use Encode;
use Log::Log4perl ':easy';
use Text::CSV_XS;
use DBI;

use JSON::Any;
my $TOTAL_COUNTIES_IN_USA = 3_007;
my $FUSION_TABLE_LIMIT = 100_000;

our $CONFIG = {
	geosku_table_name => 'geosku',
	db_path => 'sqlite.db',
};

sub date_to_name {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
	return sprintf "%d%02d%02d-%02d%02d%02d/", $year+1900, $mon+1, $mday, $hour, $min, $sec;
}

sub new {
	my $inv  = shift;
	my $args = ref($_[0])? shift : {@_};
	my $self = {
		%$args,
		sth		=> {},
		ua		=> LWP::UserAgent->new,
		jsoner	=> JSON::Any->new,
	};

	$self->{ua}->timeout(30);
	$self->{ua}->env_proxy;

	if ($self->{auth_string} and not $self->{auth_token}) {
		($self->{auth_token}) = $self->{auth_string} =~ /access_token=([^&;]+)/;
	}

	return bless $self, ref($inv) ? ref($inv) : $inv;
}

=head2 update

Creates multiple CSVs and a JSON index of which SKU is in
which CSV, because Fusion Tables only imports small CSVs at
the time of writing.

Accepts:

=over 4

=item C<include_only_skus>

Optional array of SKUs by which to filter. If this option is supplied, SKUs in C<county_distributino_path> 
that do not match an entry will be ignored.

=item  C<sku2latin_path>

UNUSED - A CSV of C<SKU,Latin> Name.

=item C<county_distributions_path>

A bar-delimited list of SKU|FIPS, one per line: C<CSC|53007>.

=item C<number_of_output_files>.

Defaults to 5.

=item C<output_path>

Directory.

=cut

sub update {
	TRACE "Enter";
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};

    $args->{number_of_output_files} ||= 5;
	if ($args->{include_only_skus}){
		$args->{include_only_skus} = { map { $_ => 1 } @{$args->{include_only_skus}} }
	}
	$args->{separator} ||= ',';

	$self->get_dbh;

	my $fh_index = -1;
	my @csv_paths;
	my @table_ids,
	my $initials_count = {};

	my $res = {
		skus2tableIndex => {},
	};

	$self->load_geo_sku_from_csv(
		path				=> $args->{county_distributions_path},
		separator			=> $args->{separator},
		include_only_skus	=> $args->{include_only_skus},
	);

	$self->{output_dir} = $self->get_dir_from_path( $args->{output_path} );
	if (!-d $self->{output_dir}) {
		mkdir $self->{output_dir} or die "$! - $self->{output_dir}";
	}

	my $tables = $self->compute_fusion_tables;

	my $i = 0;
	foreach my $table (@$tables) {
		$table->create($i++);
		$table->populate;
	}

	INFO "Create $self->{output_dir}/index.js";
	open my $FH, ">:encoding(utf8)", "$self->{output_dir}/index.js" or die "$! - $self->{output_dir}/index.js";
	my $jsonRes = $self->{jsoner}->encode( $res );
	print $FH $jsonRes;
	close $FH;

	return $jsonRes;
}

sub add_rows_to_google {
	TRACE "Enter";
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};

    my $url = 'https://www.googleapis.com/fusiontables/v2/tables'
		. '/' . $args->{table_id} . '/import'
		. '?' . $self->{auth_string};

	INFO "Posting $args->{csv_path} to $url";
	return $self->_post_blob( $url, $args->{csv_path} );
}

sub publish_table_to_google {
    TRACE "Enter";
	my $self = shift;
    my $args = ref($_[0])? shift : {@_};

	my $table = {
		name => $args->{table_name},
		isExportable => 'true',
		description => 'Table ' . $args->{table_number},
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
	};

    my $url = 'https://www.googleapis.com/fusiontables/v2/tables'
		. '?' . $self->{auth_string};

	INFO "Posting '$args->{name}' to $url";
	my $res = $self->_post_blob( $url, $table );
	$res->{tableId} = $res->{content}->{tableId};
	return $res;
}

sub _post_blob {
	my ($self, $url, $blob) = @_;

	$self->{ua}->default_header( authorization => $self->{auth_token} ) if $self->{auth_token};
	$self->{ua}->default_header( 'content-type' => 'application/json' );

	my $response = $self->{ua}->post(
		$url, 
		Content => $blob =~ /\n/ ? $self->{jsoner}->encode($blob) : $blob
	);

	my $res = {};

	if ($response->is_success) {
		$res->{content} = $self->{jsoner}->decode( $response->decoded_content );
	} else {
		$res->{error} = $response->status_line;
	}

	return $res;
}


sub load_sku2latin_from_csv {
    my $args = shift;
    my $skus = {};
    my $csv_out = Text::CSV_XS->new ({ binary => 1, auto_diag => 1 });
    INFO "Reading ",$args->{sku2latin_path};
    
	open my $IN, "<:encoding(utf8)", $args->{sku2latin_path}
        or LOGDIE "$! - $args->{sku2latin_path}";
    
	while (my $row = $csv_out->getline($IN)) {
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


sub load_geo_sku_from_csv {
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$args->{separator} ||= ',';
	my $count = 0;

	open my $IN, "<:encoding(utf8)", $args->{path}
		or LOGDIE "$! - $args->{path}";

	my $csv_input = Text::CSV_XS->new({
		sep_char 	=> $args->{separator},
		binary 		=> 1,
		auto_diag 	=> 1
	});

	while (my $row = $csv_input->getline($IN)) {
		my $sku  = uc $row->[0];
		my $fips = $row->[1];
		die 'FIPS should be numeric' if not $fips =~ /^\d+$/;
		my $geo_id2 = $fips + 0;
		if (not($args->{include_only_skus}) or exists $args->{include_only_skus}->{$sku}){
			$self->insert_geosku( $geo_id2, $sku );
			$count ++;
		}
	}
	
	close $IN;
	return $count;
}

sub get_dir_from_path {
	my ($self, $path) = @_;
	my ($dir, $ext) = $path =~ /^(.+?)(\.[^.]+)?$/;
	return $dir;
}	

sub get_dbh {
	my $self = shift;
	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$CONFIG->{db_path}","","");

	# Check for our table:
	my $sth = $self->{dbh}->table_info();
	my @tables = $self->{dbh}->selectall_array($sth);

	# If the scheme does not exist, create it:
	if (not grep { $_->[2] eq $CONFIG->{geosku_table_name}  } @tables ) {
		$sth = $self->{dbh}->prepare("CREATE TABLE $CONFIG->{geosku_table_name} (
			geo_id2	BLOB,
			sku		VARCHAR(10)
		)");
		$sth->execute or die;
		$self->{created_db} = 1;
	} 
	
	else {
		$self->{created_db} = 0;
	}

}

sub get_geoid2s_for_sku {
	my ($self, $sku) = @_;
	TRACE 'Enter for SKU ', $sku;
	LOGCONFESS 'No SKU' if not $sku;
	$self->{sth}->{get_geoid2s_for_sku} ||= $self->{dbh}->prepare_cached(
		"SELECT GEO_ID2 FROM $CONFIG->{geosku_table_name} WHERE sku = ?"
	);
	return map {$_->[0]} @{
		$self->{dbh}->selectall_arrayref( 
			$self->{sth}->{get_geoid2s_for_sku},
			{}, 
			$sku 
		)
	};
}

sub insert_geosku {
	my ($self, $geo_id2, $sku) = @_;

	$self->{sth}->{insert_geosku} ||= $self->{dbh}->prepare_cached(
		"INSERT INTO $CONFIG->{geosku_table_name} (geo_id2, sku) VALUES (?, ?)"
	);

	return $self->{sth}->{insert_geosku}->execute( $geo_id2, $sku );
}

sub get_initials {
	return [
		map {$_->[0]} shift->{dbh}->selectall_array("SELECT DISTINCT SUBSTR(sku,1,1) FROM  $CONFIG->{geosku_table_name} ORDER BY sku ASC")
	];
}

sub compute_fusion_tables {
	my $self = shift;
	Table->RESET;
	my $fusion_table_limit = shift || $FUSION_TABLE_LIMIT;
	my $counts = $self->{dbh}->selectall_arrayref(
		"SELECT COUNT(geo_id2) AS c, sku FROM $CONFIG->{geosku_table_name} GROUP BY sku ORDER BY c DESC"
	);

	# my $total = 0;
	# map { $total += $_->[0] } @$counts;

	my $tables = [
		Table->new( 
			dir => $self->{output_dir}
		)
	];
	my $table_index = 0;

	foreach my $record (@$counts) {
		if ($tables->[$table_index]->{count} + $record->[0] > $fusion_table_limit) {
			$table_index ++;
			$tables->[$table_index] = Table->new( 
				dir => $self->{output_dir}
			);
		}
		$tables->[$table_index]->add( 
			count => $record->[0],
			sku => $record->[1],
		);
	}

	return $tables;
}

1;

package Table;
use base 'IzelBase';
use Log::Log4perl ':easy';
use File::Temp ();
use Text::CSV_XS;

my $TABLES_CREATED = -1;

sub RESET  {
	my $inv = shift;
	$TABLES_CREATED = -1;
}

sub new {
	my $inv  = shift;
	my $args = ref($_[0])? shift : {@_};
	$TABLES_CREATED ++;
	my $self = {
		%$args,
		count => 0, 
		skus => [],
		index_number => exists($args->{index_number}) ? $args->{index_number} : ($TABLES_CREATED),
		dir => $args->{dir} || File::Temp::tempdir( CLEANUP => 0 ),
	};
	$self->{name} = $args->{name} || 'Table #' . $self->{index_number};
	$self = bless $self, ref($inv) ? ref($inv) : $inv;
	return $self;
}

sub add {
	my ($self, $args) = (shift, ref($_[0])? shift : {@_} );
	$self->{count} += $args->{count};
	push @{ $self->{skus} }, $args->{sku};
}

sub create {
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$self->{index_number} = $args->{index_number};
	$self->{name} = 'Table #' . $self->{index_number};

	my $create_res = $self->publish_table_to_google({
		table_name => $self->{name},
		table_number => $self->{index_number},
	});

	$self->_create_file;
}

sub _create_file {
	TRACE 'Enter _create_file with ' ,join' ', @_;
	my ($self, $obj_w_dbh, $get_geoid2s_for_sku) = @_;

	$self->require_defined_fields('dir', 'index_number');

	my $path = $self->{dir} .'/'. $self->{index_number} . '.csv';
	open my $FH, ">:encoding(utf8)", $path or die "$! - $path";

	$FH->print("GEO_ID2,SKU,\n");

	foreach my $sku (@{ $self->{skus} }) {
		TRACE 'Do SKU ', $sku;
		foreach my $geo_id2 ($obj_w_dbh->$get_geoid2s_for_sku($sku)) {
			$FH->print( "$sku,$geo_id2\n" );
		}
	}

	TRACE 'Wrote ', $path;

	return $path;
}


	# my $az;

	# while (@keys){
	# 	$fh_index ++;
	# 	$fh_index = 0 if $fh_index >= $args->{number_of_output_files};
	# 	my $initial = shift @keys;

	# 	INFO sprintf "SKUs initial %s with %s into %s",
	# 		$initial, scalar( keys %{ $az->{$initial} }), $fh_index;

	# 	foreach my $sku (sort keys %{ $az->{$initial} }){
	# 		$res->{skus2tableIndex}->{$sku} = $fh_index;

	# 		foreach my $geo_id2 (@{
	# 			$az->{$initial}->{$sku}
	# 		} ){
	# 			$self->{csv_out}->print( $OUT[$fh_index], [
	# 				$geo_id2, $sku
	# 			]);
	# 		}
	# 	}

	# 	# Terminate JSON
	# 	print $fh "]\n";
	# }

	# close $_ foreach @OUT;

	# foreach my $table ( @{$res->{response}} ) {
	# 	$self->add_rows_to_google(
	# 		table_id => $table->{tableId}, 
	# 		csv_path => shift @csv_paths,
	# 	);
	# }

1;
