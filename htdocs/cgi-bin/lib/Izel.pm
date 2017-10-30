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
use Data::Dumper;
use Encode;
use Log::Log4perl ':easy';
require  DBI;
require  JSON::Any;
require  Text::CSV_XS;

my $DEFAULT_US_COUNTIES_TABLE_ID = '1CP_uYV52MKV42Qt7O3TrpzS1sr7JBWPMIWxw4sQV';
my $TOTAL_COUNTIES_IN_USA = 3_007;
my $FUSION_TABLE_LIMIT = 100_000;

our $CONFIG = {
	geosku_table_name	=> 'geosku',
	index_table_name	=> 'table_index',
	db_path				=> 'sqlite.db',
	endpoints			=> {
		_create_table_on_google	=> 'https://www.googleapis.com/fusiontables/v2/tables',
		gsql => 'https://www.googleapis.com/fusiontables/v2/query',
	}
};

sub date_to_name {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
	return sprintf "%d%02d%02d-%02d%02d%02d/", $year+1900, $mon+1, $mday, $hour, $min, $sec;
}

sub publish_index {
	my $inv = ref($_[0]) || $_[0] eq __PACKAGE__? shift : '';
	my $args = ref($_[0])? shift : {@_};
	File::Copy::move( $args->{from}, $args->{to} );
}

sub upload_skus {
    my $inv = ref($_[0]) || $_[0] eq __PACKAGE__? shift : '';
    my $args = ref($_[0])? shift : {@_};
    TRACE 'Enter';
    my $uploaded_sku_csv_path = 'latest_skus.csv';
    $args->{skus_text} ||= [];
    if (not ref $args->{skus_text}){
        $args->{skus_text} = [ $args->{skus_text}.split(/[,\W]+/) ]
    }

    binmode $args->{skus_file_handle};

    TRACE 'Process skus' . ($args->{skus_text} || '');
    TRACE 'Write uploaded skus to ', $uploaded_sku_csv_path;

    open my $OUT,">:utf8", $uploaded_sku_csv_path or LOGDIE "$! - $uploaded_sku_csv_path";

    my $io_handle = $args->{skus_file_handle}->handle;
    binmode $io_handle;

    while (my $bytesread = $io_handle->read(my $buffer,1024)) {
        print $OUT $buffer;
    }

    close $OUT;
    close $args->{skus_file_handle};

    TRACE 'Finished writing uploaded skus to file';
    TRACE 'Call create_fusion_csv_multiple';

    my $jsonRes = Izel->new(
        auth_string          => $args->{auth_string},
    )->create(
        skus2fips_csv_path   => $uploaded_sku_csv_path,
        output_dir	    	 => $args->{output_dir},
        include_only_skus    => $args->{skus_text}
    );

    TRACE 'Done upload_skus';
    return $jsonRes;
}

sub new {
	my $inv  = shift;
	my $args = ref($_[0])? shift : {@_};
	$args->{us_counties_table_id} ||= $DEFAULT_US_COUNTIES_TABLE_ID;
	my $self = {
		%$args,
		jsoner	=> JSON::Any->new,
		sth		=> {},
	};

	if ($self->{auth_string} and not $self->{auth_token}) {
		($self->{auth_token}) = $self->{auth_string} =~ /access_token=(.+)$/;
		INFO 'SET AUTH TOKEN TO ', $self->{auth_token};
	}

	return bless $self, ref($inv) ? ref($inv) : $inv;
}

=head2 create

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

=item C<skus2fips_csv_path>

A bar-delimited list of SKU|FIPS, one per line: C<CSC|53007>.

=item C<number_of_output_files>.

Defaults to 5.

=item C<output_dir>

Directory.

=cut

sub create {
	TRACE "Enter Izel::create";
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
		path				=> $args->{skus2fips_csv_path},
		separator			=> $args->{separator},
		include_only_skus	=> $args->{include_only_skus},
	);

	$self->{output_dir} = $args->{output_dir};

	if (!-d $self->{output_dir}) {
		mkdir $self->{output_dir} or die "$! - $self->{output_dir}";
	}

	my $tables = $self->compute_fusion_tables;

	my @res;
	foreach my $table (@$tables) {
		push @res, $table->create();
	}

	return $self->create_index_file(@res);
}


sub _compose_index_file {
	my ($self, @res) = @_;
    my @skus2table_ids = $self->{dbh}->selectall_array("
        SELECT DISTINCT $CONFIG->{geosku_table_name}.sku AS sku, $CONFIG->{index_table_name}.url AS table_id
        FROM $CONFIG->{geosku_table_name}
        JOIN $CONFIG->{index_table_name}
    ");

	my $json = $self->{jsoner}->encode({
		mergedTableIds => \@res,
		skus2tableIds  =>  {
			map { $_->[0] => $_->[1] } @skus2table_ids
		}
	});

	return $json;
}

sub create_index_file {
	my ($self, @res) = @_;
	my $json = $self->_compose_index_file(@res);
	return $self->_write_index_file($json);
}

sub _write_index_file {
	my ($self, $json) = @_;
	TRACE "Create $self->{output_dir}/index.js";
	open my $FH, ">:encoding(utf8)", "$self->{output_dir}/index.js" or die "$! - $self->{output_dir}/index.js";
	print $FH $json;
	close $FH;
	INFO "Created $self->{output_dir}/index.js";
	return $json;
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
	my ($self, $wipe) = @_;
	$self->{dbh} = DBI->connect("dbi:SQLite:dbname=$CONFIG->{db_path}","","");

	# Check for our table:
	my $sth = $self->{dbh}->table_info();
	my @tables = $self->{dbh}->selectall_array($sth);

	# If the scheme does not exist, create it:
	# warn Dumper grep { warn 'xxxxxx',$_->[2];$_->[2] eq $CONFIG->{geosku_table_name}  } @tables;
	if ($wipe or not grep { $_->[2] eq $CONFIG->{geosku_table_name}  } @tables ) {
		foreach my $statement (
			"DROP TABLE IF EXISTS $CONFIG->{index_table_name}",
			"CREATE TABLE $CONFIG->{index_table_name} (
				id INTEGER AUTO_INCREMENT PRIMARY KEY,
				url VARCHAR(255)
			)",
			"DROP TABLE IF EXISTS $CONFIG->{geosku_table_name}",
			"CREATE TABLE $CONFIG->{geosku_table_name} (
				geo_id2			BLOB,
				sku				VARCHAR(10),
				merged_table_id INTEGER,
				FOREIGN KEY(merged_table_id) REFERENCES $CONFIG->{index_table_name}(merged_table_id)
			)"
		){
			$self->{dbh}->do($statement);
		}
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
		map { $_ => $self->{$_} } qw/ auth_token auth_string output_dir jsoner dbh us_counties_table_id ua/
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
use Data::Dumper;

my $TABLES_CREATED = -1;

sub RESET  {
	my $inv = shift;
	$TABLES_CREATED = -1;
}

sub new {
	my $inv  = shift;
	my $args = ref($_[0])? shift : {@_};
	$TABLES_CREATED ++;
	$args->{ua} ||= LWP::UserAgent->new;

	my $self = {
		%$args,
		jsoner	=> JSON::Any->new,
		sth		=> {},
		count => 0,
		skus => [],
		index_number => exists($args->{index_number}) ? $args->{index_number} : ($TABLES_CREATED),
	};

	$self->{ua}->timeout(30);
	$self->{ua}->env_proxy;

	$self = bless $self, ref($inv) ? ref($inv) : $inv;

	$self->require_defined_fields('output_dir');

	return $self;
}

sub first_and_last_sku {
	my $self = shift;
	@{ $self->{skus} } = sort @{$self->{skus}};
	return $self->{skus}->[0], $self->{skus}->[ $#{$self->{skus}} ];
}

sub set_name_from_skus {
	my $self = shift;
	$self->{name} = 'SKU/Geo Table #' . $self->{index_number}
		. ' (' . join(' - ', $self->first_and_last_sku()) .')';
}

sub create {
	TRACE 'Enter Izel::Table::Create';
	my $self = shift;
	$self->_create_table_on_google();
	$self->_populate_table_on_google();

	$self->_create_merge();

	$self->_update_skus_merged_table_id();

	TRACE 'Leave';
}

sub _update_skus_merged_table_id {
	my $self = shift;
	$self->require_defined_fields('skus', 'merged_table_google_id');

	$self->{sth}->{create_merged_table_id} ||= $self->{dbh}->prepare_cached("
		INSERT INTO $CONFIG->{index_table_name} (url) VALUES (?)
	");
	$self->{sth}->{create_merged_table_id}->execute($self->{merged_table_google_id});
	$self->{merged_table_id} = $self->{dbh}->last_insert_id( undef, undef, $CONFIG->{index_table_name}, undef );

	$self->{sth}->{update_skus_merged_table_id} ||= $self->{dbh}->prepare_cached("
		UPDATE $CONFIG->{geosku_table_name}
		SET merged_table_id = ?
		WHERE sku = ?
	");

	foreach my $sku (@{ $self->{skus}}) {
		$self->{sth}->{update_skus_merged_table_id}->execute(
			$self->{merged_table_id},
			$sku
		);
	}
}

sub add_count {
	my ($self, $args) = (shift, ref($_[0])? shift : {@_} );
	$self->{count} += $args->{count};
	push @{ $self->{skus} }, $args->{sku};
}

sub _create_table_on_google {
    TRACE "Enter";
	my $self = shift;

	$self->set_name_from_skus;
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

	DEBUG "Posting '$self->{name}' to ", $CONFIG->{endpoints}->{_create_table_on_google};
	my $res = $self->_post_blob( $CONFIG->{endpoints}->{_create_table_on_google}, $table );
	LOGCONFESS 'No content.tableId from Google?' if not $res->{content}->{tableId};
	$self->{table_id} = $res->{tableId} = $res->{content}->{tableId};
	INFO "Created table ID ", $self->{table_id};
	TRACE Dumper $res;
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
	DEBUG 'Inserted all rows';
	TRACE Dumper \@res;
	return @res;
}


sub _execute_gsql {
	my ($self, @gsql) = @_;
	TRACE "Posting form gSQL to ", $CONFIG->{endpoints}->{gsql};
	my $res = $self->_post_blob( $CONFIG->{endpoints}->{gsql}, \@gsql);
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
		$self->{merged_table_google_id} = $res->{content}->{rows}->[0]->[0];
	} else {
		LOGCONFESS 'Unexpected response to gsql:', $gsql, "\nResponse:", Dumper $res;
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
