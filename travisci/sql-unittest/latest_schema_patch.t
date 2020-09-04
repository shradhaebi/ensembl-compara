#!/usr/bin/env perl
# Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
# Copyright [2016-2020] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

use File::Temp qw/tempfile/;
use Test::More;

use Bio::EnsEMBL::ApiVersion;
use Bio::EnsEMBL::Test::MultiTestDB;

use Bio::EnsEMBL::Compara::Utils::Test;


## Check that the schemas test databases are fully compliant with the SQL standard

my $compara_dir = Bio::EnsEMBL::Compara::Utils::Test::get_repository_root();
my $t_dir = "${compara_dir}/modules/t";

# Initialize a MultiTestDB object
my $multitestdb = bless {}, 'Bio::EnsEMBL::Test::MultiTestDB';
$multitestdb->curr_dir($t_dir);
$multitestdb->_rebless;
$multitestdb->species('compara');

# Load the Compara schema for reference
my $current_db_name = $multitestdb->create_db_name('current_schema');
my $current_statements = Bio::EnsEMBL::Compara::Utils::Test::read_sqls("${compara_dir}/sql/table.sql");
my $current_db = Bio::EnsEMBL::Compara::Utils::Test::load_statements($multitestdb, $current_db_name, $current_statements, 'Can load the current Compara schema');
my $current_schema = Bio::EnsEMBL::Compara::Utils::Test::get_schema_from_database($current_db);

my $curr_release = software_version();
my $prev_release = $curr_release -1;


# A temporary file to store the old schema
my ($fh, $filename) = tempfile(UNLINK => 1);
close($fh);
my $url = "https://github.com/Ensembl/ensembl-compara/raw/release/$prev_release/sql/table.sql";
my $download_command = ['wget', $url, '--quiet', '--output-document', $filename];
my $test_name = "Download the previous schema from $url into $filename";
Bio::EnsEMBL::Compara::Utils::Test::test_command($download_command, $test_name);
my $previous_db_name = $multitestdb->create_db_name('previous_schema');
my $previous_statements = Bio::EnsEMBL::Compara::Utils::Test::read_sqls($filename);
my $previous_db = Bio::EnsEMBL::Compara::Utils::Test::load_statements($multitestdb, $previous_db_name, $previous_statements, 'Can load the previous Compara schema');

my @schema_patcher_command = (
    "$ENV{ENSEMBL_CVS_ROOT_DIR}/ensembl/misc-scripts/schema_patcher.pl",
    '--host'        => $multitestdb->db_conf->{'host'},
    '--port'        => $multitestdb->db_conf->{'port'},
    '--user'        => $multitestdb->db_conf->{'user'},
    '--pass'        => $multitestdb->db_conf->{'pass'},
    '--database'    => $previous_db_name,
    '--type'        => 'compara',
    '--from'        => $prev_release,
    '--release'     => $curr_release,
    #'--verbose',
    '--quiet',
    '--nointeractive',
);
Bio::EnsEMBL::Compara::Utils::Test::test_command(\@schema_patcher_command, 'Can patch the database');
my $previous_schema = Bio::EnsEMBL::Compara::Utils::Test::get_schema_from_database($previous_db);

is_deeply($current_schema, $previous_schema);

# No need to drop the database because it will be destroyed when
# $multitestdb goes out of scope

done_testing();
