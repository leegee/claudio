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
use File::Path;
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

sub map_some_skus {
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	INFO 'Enter process_some_skus:';
	$args->{skus_text} ||= [];
    if ($args->{skus_text} and not ref $args->{skus_text}){
        $args->{skus_text} = [ split(/[,\s]+/, $args->{skus_text}) ]
    }
    if (not scalar @{$args->{skus_text}}){
		LOGDIE 'No skus-text supplied! '. Dumper($args->{skus_text});
	}

	$args->{skus_text} = [sort @{$args->{skus_text}}];

	INFO 'Got ',
		(1 + $#{$args->{skus_text}}),
		' SKUs: ', join',',@{$args->{skus_text}};

	INFO 'Checking validity and upload status';

	my (@already_published, @skus_todo, @invalid_skus);
	my $count = 0;

	foreach my $sku (@{ $args->{skus_text} }){
		$count ++;
		if ($self->is_sku_valid($sku)){
			if ($self->is_sku_published($sku)){
				push(@already_published, $sku)
			} else {
				push(@skus_todo, uc $sku)
			}
		} else {
			push @invalid_skus, uc $sku;
		}
		if ($count % 100 == 0) {
			INFO 'Checked ', $count, '...';
		}
	}

	my @msg = 'You supplied '. (1 + $#{$args->{skus_text}}). ' SKUs';
	if (@invalid_skus) {
		push @msg, 'The following '. (1+$#invalid_skus).' SKUs are invalid: ', join",", @invalid_skus;
	}
	if (@already_published) {
		push @msg, 'The following '. (1+$#already_published). ' SKUs are already public: ', join",", @already_published;
	}

	if (not scalar @skus_todo) {
		unshift @msg, 'There are no SKUs from your supplied list that can be published.\n\n';
		LOGDIE join("\n\n", @msg, "\n");
	}

	INFO join '\n\n', @msg;

	my @merged_table_google_ids;
	my $tables = $self->create_fusion_tables( \@skus_todo );

	foreach my $table (@$tables) {
		$table->create();
		INFO 'Created merged table, ', $table->{merged_table_google_id};
		push @merged_table_google_ids, $table->{merged_table_google_id};
	}

	$self->{dbh}->commit();
	WARN join '\n\n', @msg;
	return;
}

sub is_sku_valid {
	my ($self, $sku) = @_;
	$self->{sth}->{is_sku_valid} ||= $self->{dbh}->prepare(
		"SELECT sku FROM $CONFIG->{geosku_table_name} WHERE SKU = ? LIMIT 1"
	);
	return $self->{dbh}->selectall_array(
		$self->{sth}->{is_sku_valid},
		{},
		uc $sku
	);
}

sub is_sku_published {
	my ($self, $sku) = @_;
	$self->{sth}->{is_sku_published} ||= $self->{dbh}->prepare("
		SELECT sku, merged_table_id FROM $CONFIG->{geosku_table_name}
		WHERE SKU = ? AND merged_table_id IS NOT NULL
		LIMIT 1
	");
	return $self->{dbh}->selectall_array(
		$self->{sth}->{is_sku_published},
		{},
		uc $sku
	);
}


sub date_to_name {
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime;
	return sprintf "%d%02d%02d-%02d%02d%02d/", $year+1900, $mon+1, $mday, $hour, $min, $sec;
}

sub publish_index {
	my $inv = ref($_[0]) || $_[0] eq __PACKAGE__? shift : '';
	my $args = ref($_[0])? shift : {@_};
	File::Copy::move( $args->{from}, $args->{to} );
}

sub copy_cgi_file {
	my $self = shift;
	my $skus_file_handle = shift;
    my $uploaded_sku_csv_path = 'latest_skus.csv';
    binmode $skus_file_handle;
    INFO 'Write uploaded skus to temp file at ', $uploaded_sku_csv_path;

    open my $OUT,">:utf8", $uploaded_sku_csv_path or LOGDIE "$! - $uploaded_sku_csv_path";

    my $io_handle = $skus_file_handle->handle;
    binmode $io_handle;

    while (my $bytesread = $io_handle->read(my $buffer,1024)) {
        print $OUT $buffer;
    }

    close $OUT;
    close $skus_file_handle;
    INFO 'Finished writing uploaded db to temp file';
	return $uploaded_sku_csv_path;
}

sub status_json {
	my $self = shift;
	my $res = {};
	eval {
		$res->{"numberOfTotalSkus"} = $self->{dbh}->selectall_arrayref(
			"SELECT COUNT(DISTINCT sku) FROM $CONFIG->{geosku_table_name}"
		)->[0]->[0];
		$res->{"numberOfMappedSkus"} = $self->{dbh}->selectall_arrayref(
			"SELECT COUNT(DISTINCT sku) FROM $CONFIG->{geosku_table_name} WHERE merged_table_id IS NOT NULL"
		)->[0]->[0];
	};
	if ($@) {
		$res = { error => $@ };
	}
	return $self->{jsoner}->encode( $res );
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
		if (not defined $self->{auth_token}) {
			LOGCONFESS 'No auth token found in auth_string, ' . $self->{auth_string};
		}
	}

	$self = bless $self, ref($inv) ? ref($inv) : $inv;
	$self->get_dbh;
	return $self;
}

sub publish_json {
    my $self = shift;
    my $args = ref($_[0])? shift : {@_};
	DEBUG 'Enter publish';
	my $res = Izel::Table->new(
		map { $_ => $self->{$_} } qw/ auth_token auth_string jsoner dbh ua/
	)->_post_blob(
		'https://www.googleapis.com/drive/v2/files/' . $args->{tableId} . '/permissions?',
		{
			role => "reader",
			type => "anyone"
		}
	);
	$self->{dbh}->do(
		"UPDATE $CONFIG->{index_table_name} SET published = 1 WHERE url = ?",
		{},
		$args->{tableId}
	);
	$self->{dbh}->commit();
	return $self->{jsoner}->encode($res);
}

sub upload_db {
    my $self = shift;
    my $args = ref($_[0])? shift : {@_};
    TRACE 'Enter upload_db';
	LOGDIE 'No skus_file_handle' if not $args->{skus_file_handle};
	my $uploaded_sku_csv_path = $self->copy_cgi_file($args->{skus_file_handle});

	eval {
		$self->wipe_google_tables();
	};

	INFO 'Have reset the DB. Now ingesting...';

    my $jsonRes = Izel->new(
		recreate_db			=> 1,
        auth_string         => $args->{auth_string},
    )->db_from_csv(
        skus2fips_csv_path  => $uploaded_sku_csv_path,
    );

    INFO 'All Done: the database has been recreated from your CSV file.';
    return $jsonRes;
}

sub augment_db {
    my $self = shift;
    my $args = ref($_[0])? shift : {@_};
    TRACE 'Enter upload_db';
	LOGDIE 'No skus_file_handle' if not $args->{skus_file_handle};
	my $uploaded_sku_csv_path = $self->copy_cgi_file($args->{skus_file_handle});

    my $jsonRes = Izel->new(
        auth_string          => $args->{auth_string},
    )->db_from_csv(
        skus2fips_csv_path   => $uploaded_sku_csv_path,
    );

    TRACE 'Done';
    return $jsonRes;
}

sub create_from_csv {
	TRACE "Enter Izel::create_from_csv";
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$self->db_from_csv(@_);
	return $self->tables_from_db();
}

sub db_from_csv {
	INFO "Enter Izel::db_from_csv";
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$self->{dbh}->commit();
	$self->ingest_sku_from_csv(
		path				=> $args->{skus2fips_csv_path},
		separator			=> $args->{separator},
		include_only_skus	=> $args->{include_only_skus},
	);
}

sub tables_from_db {
	my $self = shift;
	my @merged_table_google_ids;

	my $tables = $self->create_fusion_tables();

	foreach my $table (@$tables) {
		$table->create();
		push @merged_table_google_ids, $table->{merged_table_google_id};
	}

	$self->{dbh}->commit();
	return;
}


sub preview_db {
	my ($self, @merged_table_google_ids) = @_;
	$self->{sth}->{all_skus2table_ids} = $self->{dbh}->prepare("
        SELECT DISTINCT
		      $CONFIG->{geosku_table_name}.sku AS sku,
		      $CONFIG->{index_table_name}.url AS googleTableId,
		      $CONFIG->{index_table_name}.id AS internalTableId,
			  $CONFIG->{index_table_name}.published AS published
		 FROM $CONFIG->{geosku_table_name}
		 JOIN $CONFIG->{index_table_name}
		   ON $CONFIG->{geosku_table_name}.merged_table_id = $CONFIG->{index_table_name}.id
    ");

    my @skus2table_ids = $self->{dbh}->selectall_array(
		$self->{sth}->{all_skus2table_ids}
	);

	my @tableInternalId2googleTableId;

	my $sql = "SELECT id, url, published FROM $CONFIG->{index_table_name}";
	if (@merged_table_google_ids) {
		$sql .= " WHERE url IN ("
			. join(",", map {$self->{dbh}->quote($_)} @merged_table_google_ids)
			. ")";
	}

	@tableInternalId2googleTableId = $self->{dbh}->selectall_array($sql);

	INFO 'Got ', (1+$#tableInternalId2googleTableId), ' live tables';
	INFO 'Got ', (1+$#skus2table_ids), ' total SKUs';

	my $json = $self->{jsoner}->encode({
		sku2tableInternalId => { map { $_->[0] => $_->[2] } @skus2table_ids },
		tableInternalId2googleTableId  => { map { $_->[0] => $_->[1] } @tableInternalId2googleTableId },
		tableInternalId2published  => { map { $_->[0] => $_->[2] } @tableInternalId2googleTableId },
		googleTableId2published  => { map { $_->[1] => $_->[2] } @tableInternalId2googleTableId },
	});

	return $json;
}


sub ingest_sku_from_csv {
	INFO 'Load GEO/SKU from CSV';
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$args->{separator} ||= ',';
	$args->{commit_every} ||= 10_000;

	my $count = 0;

	open my $IN, "<:encoding(utf8)", $args->{path}
		or LOGDIE "$! - $args->{path}";

	INFO 'Reading uploaded CSV, ', $args->{path};
	INFO "Will log every $args->{commit_every} rows....";

	my $csv_input = Text::CSV_XS->new({
		sep_char 	=> $args->{separator},
		binary 		=> 1,
		auto_diag 	=> 1
	});

	my $mode;

	while (my $row = $csv_input->getline($IN)) {
		if (! defined $mode && $row->[0] eq 'SKU') {
			# "SKU","REGION","FIPS","STATE_NAME","COUNTY_NAME"
			$mode = 1;
			next;
		}
		my $sku  = uc $row->[0];
		my $fips;
		if ($mode) {
			$fips = $row->[2];
			$fips =~ s/^US//;
		} else {
			$fips = $row->[1];
		}

		# TRACE  "$fips -> $sku :: ", join",",@$row;
		LOGDIE 'FIPS should be numeric, got a row [', join(', ', @$row), ']' if not $fips =~ /^\d+$/;
		my $geo_id2 = $fips + 0;
		$self->insert_geosku( $geo_id2, $sku );
		$count ++;

		if ($count % $args->{commit_every} == 0) {
			$self->{dbh}->commit();
			INFO "Processed $count rows from the uploaded CSV file.";
		}
	}

	$self->{dbh}->commit();
	INFO "Done! Processed $count rows from the uploaded CSV file.";
	close $IN;
	return $count;
}

sub get_dir_from_path {
	my ($self, $path) = @_;
	my ($dir, $ext) = $path =~ /^(.+?)(\.[^.]+)?$/;
	return $dir;
}

sub _connect {
	my $self = shift;
	TRACE 'Enter _connect';

	# my $dsn = "dbi:SQLite:dbname=$CONFIG->{db_path}"; my $user = ''; my $pass = '';
	my $dbname = 'geosku';
	my $dsn = "dbi:mysql"; # "dbi:mysql:dbname=$dbname";
	my $user = 'root';
	my $pass = 'admin';

	$self->{dbh} = DBI->connect("DBI:mysql:", $user, $pass)
		or LOGDIE "Cannot connect to local mysql with $user:$pass";

	if ($self->{recreate_db}) {
		INFO 'Drop and create DB';
		$self->{dbh}->do("DROP DATABASE IF EXISTS $dbname") or LOGDIE "Cannot create database geosku"; # XXX
		$self->{dbh}->do("CREATE DATABASE IF NOT EXISTS $dbname") or LOGDIE "Cannot create database geosku";
	}

	$self->{dbh} = DBI->connect($dsn . ':'. $dbname, $user, $pass, {
		RaiseError => 1,
		AutoCommit => 0,
		mysql_server_prepare => 1,
		mysql_auto_reconnect => 1,
	}) or LOGCONFESS $DBI::errstr;
	TRACE 'Leave _connect';
}

sub get_dbh {
	my ($self, $wipe) = @_;
	$self->_connect;
	# Check for our table:

	if ($self->{recreate_db}) {
		INFO 'Create tables';
		foreach my $statement (
			"DROP TABLE IF EXISTS $CONFIG->{index_table_name}",
			"CREATE TABLE IF NOT EXISTS $CONFIG->{index_table_name} (
				id INTEGER AUTO_INCREMENT PRIMARY KEY,
				url VARCHAR(255),
				published TINYINT(1) DEFAULT 0,
				INDEX indexUrl (url),
				INDEX indexPublished (published)
			)",
			"DROP TABLE IF EXISTS $CONFIG->{geosku_table_name}",
			"CREATE TABLE IF NOT EXISTS $CONFIG->{geosku_table_name} (
				geo_id2			BLOB,
				sku				VARCHAR(10),
				merged_table_id INTEGER,
				INDEX indexSku (sku)
				# FOREIGN KEY(merged_table_id) REFERENCES $CONFIG->{index_table_name}(merged_table_id)
			)"
		){
			$self->{dbh}->do($statement);
			$self->{dbh}->commit();
		}
		INFO 'Created tables.';
	}
	TRACE 'Leave get_dbh';
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

# Because of https://developers.google.com/fusiontables/docs/v1/using#quota
# ACONI, ACOP
sub create_fusion_tables {
	INFO 'Enter create_fusion_tables to compute the number of tables needed....';
	my $self = shift;
	my $skus = shift;
	INFO 'We have ', scalar(@$skus), ' SKUs to publish';
	if (scalar(@$skus) == 1) {
		WARN 'One SKU, ', @$skus;
	}
	Izel::Table->RESET;
	my $fusion_table_limit = shift || $FUSION_TABLE_LIMIT;

	# TODO this as bucket brigade
	my $sql = "SELECT COUNT(geo_id2) AS c, sku
		FROM $CONFIG->{geosku_table_name}
		WHERE merged_table_id IS NULL";

	if (@$skus) {
		$sql .= " AND sku IN ("
		. join(",", map { $self->{dbh}->quote($_) } @$skus )
		. ")";
	}
	$sql .= " GROUP BY sku ORDER BY c DESC";

	INFO $sql;

	my $counts = $self->{dbh}->selectall_arrayref($sql);

	if (not $counts) {
		LOGCONFESS 'Nothing?! ', $sql, "\n\n", Dumper($counts);
	}

	my @interleaved;
	while (@$counts) {
		push @interleaved, shift @$counts;
		push @interleaved, pop @$counts if @$counts;
		push @interleaved, pop @$counts if @$counts;
	}

	my $table_args = {
		map { $_ => $self->{$_} } qw/ auth_token auth_string jsoner dbh us_counties_table_id ua/
	};

	my $tables = [
		Izel::Table->new( $table_args )
	];
	my $table_index = 0;

	foreach my $record (@interleaved) {
		# Max 100,000 rows per table for queries
		# TODO add count of data size < 250 MB per tble, < 1 GB in total,
		# TODO If big record doesn't fit, find a smaller one.
		INFO 'Record: ', Dumper($record);
		if ($tables->[$table_index]->{count} + $record->[0] > $fusion_table_limit) {
			$tables->[$table_index]->create();
			$table_index ++;
			$tables->[$table_index] = Izel::Table->new( $table_args );
		}
		$tables->[$table_index]->add_sku(
			count => $record->[0],
			sku => $record->[1],
		);
	}

	INFO 'Leave create_fusion_tables after making ', scalar @$tables;
	return $tables;
}

sub wipe_google_tables {
	TRACE 'Enter';
	my $self = shift;
	my @tables = $self->{dbh}->selectall_array("
		SELECT DISTINCT url FROM $CONFIG->{index_table_name}
	");
	TRACE 'URLs for tables: ', join ', ', @tables;
	foreach my $record (@tables) {
		TRACE 'Delete table, ', $record->[0];
		Izel::Table->new(
			url => $record->[0],
			dbh => $self->{dbh},
			auth_string => $self->{auth_string},
		)->delete_by_url();
	}
	$self->{dbh}->do("DELETE FROM $CONFIG->{index_table_name}");
	$self->{dbh}->do("UPDATE $CONFIG->{geosku_table_name} SET merged_table_id = NULL");
	$self->{dbh}->commit();
}

sub get_skus_not_uploaded {
	my $self = shift;
	my $args = ref($_[0])? shift : {@_};
	$args->{page_size} ||= 1000;
	$self->{sth}->{get_skus_not_uploaded} ||= $self->{dbh}->prepare("
		SELECT sku FROM $CONFIG->{geosku_table_name}
		WHERE merged_table_id IS NULL
		LIMIT ?
	");
	return map {$_->[0]} @{
		$self->{dbh}->selectall_arrayref(
			$self->{sth}->{get_skus_not_uploaded},
			{},
			$args->{page_size}
		)
	};
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

	return $self;
}

sub first_and_last_sku {
	my $self = shift;
	@{ $self->{skus} } = sort @{$self->{skus}};
	return $self->{skus}->[0], $self->{skus}->[ $#{$self->{skus}} ];
}

sub set_name_from_skus {
	my $self = shift;
	my $prefix = $_[0] ? "$_[0] " : "";
	$self->{name} = $prefix . 'Table #' . $self->{index_number}
		. ' (' . join(' - ', $self->first_and_last_sku()) .')';
}

sub create {
	TRACE 'Enter Izel::Table::Create';
	my $self = shift;
	if (@{ $self->{skus} }){
		$self->_create_table_on_google();
		$self->_populate_table_on_google();
		$self->_create_merge();
		$self->_update_skus_merged_table_id();
	}
	TRACE 'Leave';
}

sub _update_skus_merged_table_id {
	my $self = shift;
	$self->require_defined_fields('skus', 'merged_table_google_id');
	TRACE 'Enter _update_skus_merged_table_id for ', $#{ $self->{skus}}, ' skus';
	$self->{sth}->{create_merged_table_id} ||= $self->{dbh}->prepare_cached("
		INSERT INTO $CONFIG->{index_table_name} (url) VALUES (?)
	");
	$self->{sth}->{create_merged_table_id}->execute( $self->{merged_table_google_id} );
	$self->{merged_table_id} = $self->{dbh}->last_insert_id( undef, undef, $CONFIG->{index_table_name}, undef );

	$self->{sth}->{update_skus_merged_table_id} ||= $self->{dbh}->prepare_cached("
		UPDATE $CONFIG->{geosku_table_name}
		SET merged_table_id = ?
		WHERE sku = ?
	");

	foreach my $sku (@{ $self->{skus}}) {
		TRACE 'update_skus_merged_table_id ', $sku;
		$self->{sth}->{update_skus_merged_table_id}->execute(
			$self->{merged_table_id},
			$sku
		);
	}

	$self->{dbh}->commit();
	TRACE 'Leave _update_skus_merged_table_id';
}

sub add_sku {
	my ($self, $args) = (shift, ref($_[0])? shift : {@_} );
	$self->{count} += $args->{count};
	push @{ $self->{skus} }, $args->{sku};
}

sub _create_table_on_google {
    TRACE "Enter _create_table_on_google";
	my $self = shift;

	$self->set_name_from_skus('SKU/Geo');
	$self->require_defined_fields(qw/ index_number name /);

	my $table = {
		name => $self->{name},
		isExportable => 'true',
		description => $self->{name} . ' - table ' . $self->{index_number},
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

	INFO "Posting '$self->{name}' to ", $CONFIG->{endpoints}->{_create_table_on_google};
	my $res = $self->_post_blob( $CONFIG->{endpoints}->{_create_table_on_google}, $table );
	LOGCONFESS 'No content.tableId from Google when creating table? Res='.(Dumper $res) if not $res->{content}->{tableId};
	$self->{table_id} = $res->{tableId} = $res->{content}->{tableId};
	INFO "Created empty table ID / name: ", $self->{table_id}, ' / ', $self->{name};
	TRACE Dumper $res;
	return $res;
}

# If $payload is a string, it is assumed to be a path to a file;
# if it is a reference to a hash, it is assumed to be JSON.
# if it is a reference to an array, it is assumed to be gSQL.
sub _post_blob {
	my ($self, $url, $payload) = @_;
	TRACE 'Enter _post_blob for ', $url;
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
		ERROR 'Response: ', $response->status_line;
		$res->{error} = $response->status_line;
	}

	TRACE 'Leave _post_blob';
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
	TRACE 'Enter get_geoid2s_for_sku for SKU ', $sku;
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
	my $self = shift;
	TRACE 'Enter _populate_table_on_google for '. $self->{name};
	$self->require_defined_fields(qw/ table_id count skus /);

	my $statements = 0;	# Up to 500 INSERTs
	my $gsql = '';

	foreach my $sku (@{ $self->{skus} }) {
		INFO 'SKU: ', $sku;
		my @geo_id2s = $self->get_geoid2s_for_sku($sku);
		INFO 'Got to do ',($#geo_id2s), ' FIPs...';
		foreach my $geo_id2 (@geo_id2s) {
			if ($statements >= 500 ) {
				TRACE 'Call interim insert';
				INFO 'Calling Google to insert 500 records';
				$self->_execute_gsql($gsql);
				$statements = 0;
			}
			$gsql .= sprintf "INSERT INTO %s (GEO_ID2, SKU) VALUES ('%s', '%s');\n",
				$self->{table_id}, $geo_id2, $sku;
		}
	}
	TRACE 'Call final insert';
	$self->_execute_gsql($gsql);
	INFO "Inserted all rows gSQL to Google for this table,\nleaving _populate_table_on_google for $self->{name}";
	return 1;
}


sub _execute_gsql {
	my ($self, @gsql) = @_;
	INFO "Posting form gSQL to ", $CONFIG->{endpoints}->{gsql};
	my $res = $self->_post_blob( $CONFIG->{endpoints}->{gsql}, \@gsql);
	INFO 'Executed gsql';
	return $res;
}

# https://developers.google.com/fusiontables/docs/v2/sql-reference#createView
sub _create_merge {
	my $self = shift;
	$self->set_name_from_skus('Merged');
	TRACE "Create merge table $self->{name}";
	my $new_table_name = $self->{name};
	my $gsql = "CREATE VIEW '$new_table_name' AS (
		SELECT * FROM $self->{table_id} AS Skus
			LEFT OUTER JOIN $self->{us_counties_table_id} AS Map
				ON Map.GEO_ID2 = Skus.GEO_ID2
	)";
	TRACE $gsql;
	my $res = $self->_execute_gsql($gsql);
	if ($res->{content} and $res->{content}->{rows}) {
		$self->{table_id} = $self->{merged_table_google_id} = $res->{content}->{rows}->[0]->[0];
		INFO "Created merged table", join ' ', $self->{name}, $self->{merged_table_google_id}, $self->{table_id};
	} else {
		LOGCONFESS 'Unexpected response to gsql:', $gsql, "\nResponse:", Dumper $res;
	}
}

sub delete_by_url {
	my $self = shift;
	$self->require_defined_fields('url');
	my $url = 'https://www.googleapis.com/fusiontables/v2/tables/'
		. $self->{url} . '?' . $self->{auth_string};
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
	$params{message} =~ s/[\n\r\f]/<br>/gs;
	$params{message} =~ s/"/&quot;/gs;
	printf "<p class='loglevel_%s'>%s</p>\n", $params{level}, $params{message};
}

1;
