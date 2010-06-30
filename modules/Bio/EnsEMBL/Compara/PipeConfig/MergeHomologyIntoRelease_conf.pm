
=pod 

=head1 NAME

  Bio::EnsEMBL::Compara::PipeConfig::MergeHomologyIntoRelease_conf

=head1 SYNOPSIS

    init_pipeline.pl Bio::EnsEMBL::Compara::PipeConfig::MergeHomologyIntoRelease_conf -password <your_password>

=head1 DESCRIPTION  

    A pipeline to merge the "homology side" of the Compara release into the main release database

=head1 CONTACT

  Please contact ehive-users@ebi.ac.uk mailing list with questions/suggestions.

=cut

package Bio::EnsEMBL::Compara::PipeConfig::MergeHomologyIntoRelease_conf;

use strict;
use warnings;

use base ('Bio::EnsEMBL::Compara::PipeConfig::ComparaGeneric_conf');

=head2 default_options

    Description : Implements default_options() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that is used to initialize default options.
                  In addition to the standard things it defines four options:
                    o('copying_capacity')   defines how many tables can be dumped and zipped in parallel
                
                  There are rules dependent on two options that do not have defaults (this makes them mandatory):
                    o('password')       your read-write password for creation and maintenance of the hive database

=cut

sub default_options {
    my ($self) = @_;
    return {
        'ensembl_cvs_root_dir' => $ENV{'HOME'}.'/work',     # some Compara developers might prefer $ENV{'HOME'}.'/ensembl_main'

        'pipeline_name' => 'compara_full_merge',            # name used by the beekeeper to prefix job names on the farm

        'pipeline_db' => {
            -host   => 'compara2',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => $ENV{USER}.'_'.$self->o('pipeline_name'),
        },

        'merged_homology_db' => {
            -host   => 'compara2',
            -port   => 3306,
            -user   => 'ensro',
            -pass   => '',
            -dbname => 'lg4_compara_homology_merged',
        },

        'rel_db' => {
            -host   => 'compara1',
            -port   => 3306,
            -user   => 'ensadmin',
            -pass   => $self->o('password'),
            -dbname => 'kb3_ensembl_compara_59',
        },

        'skipped_tables' => [ 'meta', 'analysis', 'ncbi_taxa_name', 'ncbi_taxa_node', 'species_set', 'species_set_tag', 'genome_db', 'method_link', 'method_link_species_set' ],

        'copying_capacity'  => 10,                                  # how many tables can be dumped and re-created in parallel (too many will slow the process down)
    };
}

=head2 pipeline_create_commands

    Description : Implements pipeline_create_commands() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that lists the commands that will create and set up the Hive database.
                  In addition to the standard creation of the database and populating it with Hive tables and procedures it also creates a directory for storing the output.

=cut

sub pipeline_create_commands {
    my ($self) = @_;
    return [
        @{$self->SUPER::pipeline_create_commands},  # inheriting database and hive tables' creation
    ];
}

=head2 pipeline_analyses

    Description : Implements pipeline_analyses() interface method of Bio::EnsEMBL::Hive::PipeConfig::HiveGeneric_conf that defines the structure of the pipeline: analyses, jobs, rules, etc.
                  Here it defines two analyses:

                    * 'generate_job_list'   generates a list of tables to be copied from master_db

                    * 'copy_table'          dumps tables from source_db and re-creates them in pipeline_db

=cut

sub pipeline_analyses {
    my ($self) = @_;
    return [
        {   -logic_name => 'generate_job_list',
            -module     => 'Bio::EnsEMBL::Hive::RunnableDB::JobFactory',
            -parameters => {
                'input_id'        => { 'table_name' => '#_range_start#' },
                'db_conn'         => $self->o('merged_homology_db'),
                'skipped_tables'  => $self->o('skipped_tables'),
                'fan_branch_code' => 2,
            },
            -input_ids => [
                { 'inputquery' => "SELECT table_name FROM information_schema.tables WHERE table_schema ='#mysql_dbname:db_conn#' AND table_name NOT IN (#csvq:skipped_tables#) AND table_rows" },
            ],
            -flow_into => {
                2 => [ 'copy_table'  ],
            },
        },

        {   -logic_name    => 'copy_table',
            -module        => 'Bio::EnsEMBL::Hive::RunnableDB::SystemCmd',
            -parameters    => {
                'db_conn'     => $self->o('merged_homology_db'),
                'dest_conn'   => $self->o('rel_db'),
                'cmd'         => 'mysqldump #mysql_conn:db_conn# #table_name# | sed "s/ENGINE=InnoDB/ENGINE=MyISAM/" | mysql #mysql_conn:dest_conn#',
            },
            -hive_capacity => $self->o('copying_capacity'),       # allow several workers to perform identical tasks in parallel
        },
    ];
}

1;

