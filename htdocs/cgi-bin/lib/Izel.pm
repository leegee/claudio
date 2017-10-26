use strict;
use warnings;

# See https://developers.google.com/fusiontables/docs/v2/using#ImportingRowsIntoTables
# Imports: https://support.google.com/fusiontables/answer/171181?hl=en

package IzelBase;
use Data::Dumper;
use Log::Log4perl ':easy';

sub require_defined_fields {
	my ($self, @fields) = @_;
	my @missing = grep {
		not exists $self->{$_} 
		or not defined $self->{$_}
	} @fields;
	LOGCONFESS 'Missing fields: ' . join(', ', @missing) . "\nin " . Dumper($self) if @missing;
}

package Izel;
use base 'IzelBase';
use File::Temp ();
use Data::Dumper;
use Encode;
use Log::Log4perl ':easy';
use DBI;
use JSON::Any;

my $US_COUNTIES_TABLE_ID = '1CP_uYV52MKV42Qt7O3TrpzS1sr7JBWPMIWxw4sQV';
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
		us_counties_table_id => $US_COUNTIES_TABLE_ID,
		jsoner	=> JSON::Any->new,
		sth		=> {},
	};

	if ($self->{auth_string} and not $self->{auth_token}) {
		($self->{auth_token}) = $self->{auth_string} =~ /access_token=(.+)$/;
		INFO 'SET AUTH TOKEN TO ', $self->{auth_token};
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
	my @paths;
	my @table_ids,
	my $initials_count = {};

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

	my @res;
	foreach my $table (@$tables) {
		push @res, $table->create();
	}

	# TRACE 'Responses: ', Dumper(\@res);

	# my $jsonRes = $self->{jsoner}->encode( {
	# 	res => \@res
	# });

	# INFO "Create $self->{output_dir}/index.js";
	# open my $FH, ">:encoding(utf8)", "$self->{output_dir}/index.js" or die "$! - $self->{output_dir}/index.js";
	# print $FH $jsonRes;
	# close $FH;

	# return $jsonRes;
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
		LOGDIE 'FIPS should be numeric, got a row [', join(', ', @$row), ']' if not $fips =~ /^\d+$/;
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
	Izel::Table->RESET;
	my $fusion_table_limit = shift || $FUSION_TABLE_LIMIT;
	my $counts = $self->{dbh}->selectall_arrayref(
		"SELECT COUNT(geo_id2) AS c, sku FROM $CONFIG->{geosku_table_name} GROUP BY sku ORDER BY c DESC"
	);

	my $table_args = {
		map { $_ => $self->{$_} } qw/ auth_token auth_string output_dir jsoner dbh us_counties_table_id /
	};

	my $tables = [
		Izel::Table->new( $table_args )
	];
	my $table_index = 0;

	foreach my $record (@$counts) {
		if ($tables->[$table_index]->{count} + $record->[0] > $fusion_table_limit) {
			$tables->[$table_index]->create();
			$table_index ++;
			$tables->[$table_index] = Izel::Table->new( $table_args );
		}
		$tables->[$table_index]->add_count( 
			count => $record->[0],
			sku => $record->[1],
		);
	}

	return $tables;
}

1;

package Izel::Table;
use base 'IzelBase';
use LWP::UserAgent();
use JSON::Any;
use Log::Log4perl ':easy';
use File::Temp ();
use Text::CSV_XS;
use Data::Dumper;

my $CSV_EOL = "\n";
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
		jsoner	=> JSON::Any->new,
		ua		=> LWP::UserAgent->new,
		sth		=> {},
		count => 0, 
		skus => [],
		index_number => exists($args->{index_number}) ? $args->{index_number} : ($TABLES_CREATED),
		output_dir => $args->{output_dir} || File::Temp::tempdir( CLEANUP => 0 ),
	};

	$self->{ua}->timeout(30);
	$self->{ua}->env_proxy;
	$self->{name} = $args->{name} || 'Table #' . $self->{index_number};

	$self = bless $self, ref($inv) ? ref($inv) : $inv;
	return $self;
}

sub create {
	TRACE 'Enter';
	my $self = shift;
	$self->_create_table_on_google();
	$self->_populate_table_on_google();
	
	my $res = $self->_create_merge();

	# if ($res->{mergedtableid}) {
	# 	my $delete_res = $self->delete();
	# }

	TRACE 'Leave';
	return $res;
}

sub add_count {
	my ($self, $args) = (shift, ref($_[0])? shift : {@_} );
	$self->{count} += $args->{count};
	push @{ $self->{skus} }, $args->{sku};
}

sub _create_table_on_google {
    TRACE "Enter";
	my $self = shift;
	$self->require_defined_fields(qw/ index_number name /);

	my $table = {
		name => $self->{name},
		isExportable => 'true',
		description => 'Table ' . $self->{index_number},
		columns => [ 
			{
				name => "GEO_ID2",
				type => "STRING",
				kind => "fusiontables#column",
				columnId => 1,
			},
			{
				name => "SKU",
				type => "STRING",
				kind => "fusiontables#column",
				columnId => 2,
			},
		]
	};

    my $url = 'https://www.googleapis.com/fusiontables/v2/tables';

	INFO "Posting '$self->{name}' to $url";
	my $res = $self->_post_blob( $url, $table );
	$self->{table_id} = $res->{tableId} = $res->{content}->{tableId};
	INFO "Created table ID ", $self->{table_id};
	INFO Dumper $res;
	return $res;
}

# If $payload is a string, it is assumed to be a path to a file;
# if it is a reference to a hash, it is assumed to be JSON.
# if it is a reference to an array, it is assumed to be gSQL.
sub _post_blob {
	my ($self, $url, $payload) = @_;
	TRACE 'Enter for ', $url;
	my $isFormData;

	if (ref $payload) {
		if (ref $payload eq 'ARRAY') {
			TRACE 'Is form data';
			$payload = { 
				sql => join " ; ", @$payload
			};
			$isFormData = 1;
			# $self->{ua}->default_header( 'content-type' => 'application/json' );
		} else {
			TRACE 'Is json data';
			$payload = $self->{jsoner}->encode($payload);
			$self->{ua}->default_header( 'content-type' => 'application/json' );
		}
	} else {
		TRACE 'File path: ', $payload;
		$self->{ua}->default_header( 'content-type' => 'application/octet-stream' );
	}

	# $self->{ua}->default_header( Authorization => $self->{auth_token} ) if $self->{auth_token};

	$url .= ($url !~ /\?/ ? '?' : '&') . $self->{auth_string};

	TRACE 'Final URL:', $url;

	my $response = $self->{ua}->post(
		$url, 
		($isFormData ? $payload : (Content => $payload))
	);

	# DEBUG Dumper $response;

	my $res = {
		content => $response->header('content-type') =~ /json/ 
			? $self->{jsoner}->decode( $response->decoded_content ) 
			: $response->decoded_content
	};

	if ($response->is_success) {
		INFO 'OK';
		# $res->{content} = $self->{jsoner}->decode( $response->decoded_content ),
	} else {
		INFO 'Response: ', $response->status_line;
		$res->{error} = $response->status_line;
	}

	TRACE '_post_blob return: ', Dumper $res;
	return $res;
}

# https://developers.google.com/fusiontables/docs/v2/reference/table/importRows
sub upload_csv_rows {
	my ($self, $path) = @_;
	TRACE "Enter upload_csv_rows with ", $path;
	$self->require_defined_fields('table_id');
			   
    my $url = 'https://www.googleapis.com/upload/fusiontables/v2/tables/'
		. $self->{table_id} . '/import?uploadType=media';

	INFO "Posting $path to $url";
	return $self->_post_blob( $url, $path );
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


# https://developers.google.com/fusiontables/docs/v2/sql-reference
# https://developers.google.com/fusiontables/docs/v2/using#insertRow
sub _populate_table_on_google {
	TRACE 'Enter';
	my $self = shift;
	my $url = 'https://www.googleapis.com/fusiontables/v2/query';
	$self->require_defined_fields(qw/ table_id count skus /);

	my $statements = 0;	# Up to 500 INSERTs 
	my $gsql = '';
	my @res;

	foreach my $sku (@{ $self->{skus} }) {
		my @geo_id2s = $self->get_geoid2s_for_sku($sku);
		foreach my $geo_id2 (@geo_id2s) {
			if ($statements >= 500 ) {
				TRACE 'Call interim insert';
				push @res, $self->_execute_gsql($gsql);
				$statements = 0;
			}
			$gsql .= sprintf "INSERT INTO %s (GEO_ID2, SKU) VALUES ('%s', '%s');\n",
				$self->{table_id}, $geo_id2, $sku;
		}
	}
	TRACE 'Call final insert';
	push @res, $self->_execute_gsql($gsql);
	TRACE 'Inserted all rows';
	INFO Dumper \@res;
	return @res;
}


sub _execute_gsql {
	my ($self, @gsql) = @_;
	my $url = 'https://www.googleapis.com/fusiontables/v2/query';
	TRACE "Posting form gSQL to $url";
	my $res = $self->_post_blob( $url, \@gsql);
	return $res;
}

# https://developers.google.com/fusiontables/docs/v2/sql-reference#createView
sub _create_merge {
	TRACE 'Enter';
	my $self = shift;
	my $new_table_name = 'Table Merge ' . $self->{index_number};
	my $gsql = "CREATE VIEW '$new_table_name' AS (
		SELECT * FROM $self->{table_id} AS Skus
			LEFT OUTER JOIN $self->{us_counties_table_id} AS Map
				ON Map.GEO_ID2 = Skus.GEO_ID2
	)";
	TRACE $gsql;
	my $res = $self->_execute_gsql($gsql);
	if ($res->{content} and $res->{content}->{rows}) {
		return { mergedTableId => $res->{content}->{rows}->[0]->[0] }
	} else {
		return $res;
	}
}

sub delete {
	my $self = shift;
	$self->require_defined_fields('table_id');
	my $url = 'https://www.googleapis.com/fusiontables/v2/tables/'
		. $self->{table_id} . '?' . $self->{auth_string};
	INFO 'Delete ', $url;
	my $response = $self->{ua}->delete($url);
	my $res = {
		url => $url,
		content => $response->header('content-type') =~ /json/ 
			? $self->{jsoner}->decode( $response->decoded_content ) 
			: $response->decoded_content
	};

	if ($response->is_success) {
		INFO 'OK';
	} else {
		INFO 'Response: ', $response->status_line;
		$res->{error} = $response->status_line;
	}

	return $res;
}

1;

package JsonRealTime;

$|++;

sub new {
	my ($class, %options) = @_;
	my $self = { %options };
	bless $self, $class;
	return $self;
}

sub log {
	my ($self, %params) = @_;
    $params{message} =~ s/"/\\"/sg;
	print '{"msg": "', $params{message}, '"}', "\n";
}

1;

package HtmlRealTime;

$|++;

sub new {
	my ($class, %options) = @_;
	my $self = { %options };
	bless $self, $class;
	$self->{jsoner} = JSON::Any->new;
	return $self;
}

sub log {
	my ($self, %params) = @_;
	$params{message} =~ s/\n/<br>/gs;
	$params{message} =~ s/"/&quot;/gs;
	printf "<p class='loglevel_%s'>%s</p>\n", $params{level}, $params{message};
}

1;
