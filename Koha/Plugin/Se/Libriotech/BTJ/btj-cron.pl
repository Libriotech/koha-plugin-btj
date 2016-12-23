#!/usr/bin/perl

# Copyright 2016 Magnus Enger Libriotech

=head1 NAME

btj-cron.pl - Process requests from BTJ after receiving them.

=head1 SYNOPSIS

 sudo koha-shell -c "perl btj-cron.pl -v" <instancename>
 
=cut

use Koha::Plugins;
use Koha::Plugin::Se::Libriotech::BTJ;
use C4::Context;

use YAML::Syck;
use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Modern::Perl;

# Get options
my ( $configfile, $limit, $verbose, $debug ) = get_options();

# Check that the config file exists
if ( !-e $configfile ) {
    say "The file $configfile does not exist...";
    exit;
}
my $config = LoadFile( $configfile );
$config->{'verbose'} = $verbose;
$config->{'debug'}   = $debug;

my $btj  = Koha::Plugin::Se::Libriotech::BTJ->new;
my $table = $btj->get_qualified_table_name('requests');

my $dbh = C4::Context->dbh;
my $query = "SELECT * FROM $table WHERE processed = 0";
my $sth = $dbh->prepare($query);
$sth->execute();

my $row_count = 0;
while ( my $row = $sth->fetchrow_hashref() ) {

    say "$row->{'request_id'}: \"$row->{'title'}\" $row->{'marcorigin'} $row->{'titleno'}" if $verbose;

    if ( $row->{'status'} == 1 ) {

        # Open order (Swedish: "öppen order")
        $btj->process_open_order( $row, $config );

    } elsif ( $row->{'status'} == 2 ) {

        # Delivered (Swedish: "levererad")
        $btj->process_delivered_order( $row, $config );

    } elsif ( $row->{'status'} == 3 ) {

        # Invoiced (Swedish: "fakturerad")
        # No need to do anything here

    } elsif ( $row->{'status'} == 4 ) {

        # Cancelled (Swedish: "annullerad")
        $btj->process_cancelled_order( $row, $config );

    } else {
        say "We have a request with an illegal status ($row->{'status'})";
    }

    $row_count++;
    last if $limit && $row_count == $limit;

}

=head1 OPTIONS

=over 4

=item B<-c, --configfile>

Path to configfile.

=item B<-l, --limit>

Only process the n first records.

=item B<-v --verbose>

More verbose output.

=item B<-d --debug>

Even more verbose output.

=item B<-h, -?, --help>

Prints this help message and exits.

=back

=cut

sub get_options {

    # Options
    my $configfile = '';
    my $limit      = '', 
    my $verbose    = '';
    my $debug      = '';
    my $help       = '';

    GetOptions (
        'i|configfile=s' => \$configfile,
        'l|limit=i'      => \$limit,
        'v|verbose'      => \$verbose,
        'd|debug'        => \$debug,
        'h|?|help'       => \$help
    );

    pod2usage( -exitval => 0 ) if $help;
    pod2usage( -msg => "\nMissing Argument: -c, --configfile required\n", -exitval => 1 ) if !$configfile;

    return ( $configfile, $limit, $verbose, $debug );

}

=head1 AUTHOR

Magnus Enger, <magnus [at] libriotech.no>

=head1 LICENSE

    Copyright 2016 Magnus Enger, Libriotech <magnus@libriotech.no>

    This file is part of koha-plugin-btj.

    koha-plugin-btj is free software; you can redistribute it and/or modify it
    under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 3 of the License, or
    (at your option) any later version.

    koha-plugin-btj is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with koha-plugin-btj; if not, see <http://www.gnu.org/licenses>.

=cut
