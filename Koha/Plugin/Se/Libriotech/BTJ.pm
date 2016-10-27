package Koha::Plugin::Se::Libriotech::BTJ;

# Copyright 2016 Magnus Enger, Libriotech <magnus@libriotech.no>
#
# This file is part of koha-plugin-btj.
#
# koha-plugin-btj is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# koha-plugin-btj is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with koha-plugin-btj; if not, see <http://www.gnu.org/licenses>.

use C4::Biblio;
use C4::Items;

use MARC::Record;
use MARC::File::XML;
use Catmandu::Importer::SRU;
use Catmandu::Exporter::MARC;
use Data::Dumper;
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access

## Here we set our plugin version
our $VERSION = "0.0.2";

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'BTJ import',
    author          => 'Magnus Enger, Libriotech',
    description     => 'Receive aquisitions data from BTJ',
    date_authored   => '2016-10-18',
    date_updated    => '2016-10-18',
    minimum_version => '16.04',
    maximum_version => undef,
    version         => $VERSION,
};

## This is the minimum code required for a plugin's 'new' method
## More can be added, but none should be removed
sub new {
    my ( $class, $args ) = @_;

    ## We need to add our metadata here so our base class can access it
    $args->{'metadata'} = $metadata;
    $args->{'metadata'}->{'class'} = $class;

    ## Here, we call the 'new' method for our base class
    ## This runs some additional magic and checking
    ## and returns our actual $self
    my $self = $class->SUPER::new($args);

    return $self;
}

# FIXME Is this needed?
## If your tool is complicated enough to needs it's own setting/configuration
## you will want to add a 'configure' method to your plugin like so.
## Here I am throwing all the logic into the 'configure' method, but it could
## be split up like the 'report' method is.
sub configure {
    my ( $self, $args ) = @_;
    my $cgi = $self->{'cgi'};

    unless ( $cgi->param('save') ) {
        my $template = $self->get_template({ file => 'configure.tt' });

        ## Grab the values we already have for our settings, if any exist
        $template->param(
            foo => $self->retrieve_data('foo'),
            bar => $self->retrieve_data('bar'),
        );

        print $cgi->header();
        print $template->output();
    }
    else {
        $self->store_data(
            {
                foo                => $cgi->param('foo'),
                bar                => $cgi->param('bar'),
                last_configured_by => C4::Context->userenv->{'number'},
            }
        );
        $self->go_home();
    }
}

## This is the 'install' method. Any database tables or other setup that should
## be done when the plugin if first installed should be executed in this method.
## The installation method should always return true if the installation succeeded
## or false if it failed.
sub install() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('requests');

    return C4::Context->dbh->do( "
        CREATE TABLE $table (
            request_id  int(32) NOT NULL auto_increment, -- Primary key
            suppliercode char(12) not null, -- SupplierCode: Leverantörens kod, t.ex. ”BTJ” för BTJ. Vi skickar ”BTJ”, ”BTJ-MD” eller ”BTJ-PR” beroende på vad det är för typ av order.
            customerno char(12) not null,   -- CustomerNoCustomer: Vilket kundnummer som lagt ordern, motsvaras av kostnadsställer/filial/avdelning.
            author varchar(255),            -- Author: Artikelns författare (om aktuellt).
            title varchar(255),             -- Title: Artikelns titel.
            isbn char(24),                  -- Isbn: Artikelns ISBN.
            classification char(24),        -- Classification: BTJ:s standardklassifikation (i SAB)
            purchasenote varchar(255),      -- PurchaseNote: Anteckning som angavs vid inköpet.
            articleno char(24),             -- ArticleNo: Artikelnummer
            price char(24),                 -- Price: Pris
            currency char(12),              -- Currency: Valuta
            deliverydate char(32),          -- DeliveryDate: Uppskattat skeppningsdatum.
            infonote varchar(255),          -- InfoNote: Typ av vara (T ex plastad, förlagsband, CD).
            noofcopies int not null,        -- NoOfCopies: Antal
            orderdate char(32),             -- OrderDate: Orderdatum
            titleno char(32) not null,      -- TitleNo: BurkNummer eller Librisnummer beroende på inställning.
            marcorigin char(12) not null,   -- MarcOrigin: Om BurkNummer (”BTJ”)eller Librisnummer (”LIBRIS”)
            department varchar(255),        -- Department: Värde som användaren angav när ordern lades (avdelning)
            localshelf varchar(255),        -- LocalShelf: Värde som användaren angav när ordern lades (placering)
            loanperiod varchar(255),        -- LoanPeriod: Värde som användaren angav när ordern lades (lånetid)
            shelfmarc varchar(255),         -- ShelfMarc: Värde som användaren angav när ordern lades (avvikande hyllsignatur)
            accountv varchar(255),          -- AccountV: Värde som användaren angav när ordern lades (anslag)
            status int not null default 0,  -- Status: Orderns status (1=Öppen order, 2= levererad, 3= fakturerad, 4=annullerad)
            origindata varchar(255),        -- OriginData: Unikt värde för varje orderrad, om en LINK beställning så kommer den därifrån annars genererar vi ett unikt värde för varje orderrad.
            remote_ip char(16),
            processed tinyint(1) not null default 0,
            added timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, 
            PRIMARY KEY (request_id)
        ) ENGINE = INNODB;
    " );
}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    my $table = $self->get_qualified_table_name('requests');

    return C4::Context->dbh->do("DROP TABLE $table");
}

=head2 process_open_order

=cut

sub process_open_order {

    my ( $self, $req, $config ) = @_;

    return unless $req->{'status'} == 1;

    # Get the record
    my $record = $self->get_record( $req->{'marcorigin'}, $req->{'titleno'}, $config );
    unless ( $record ) {
        say "Something went wrong, we do not have a record for $req->{'marcorigin'} $req->{'titleno'}";
        return undef;
    }
    say Dumper $record if $config->{'debug'};

    # Add record and items to Koha
    # FIXME Should frameworkcode be configurable?
    my ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '' );

    say "Saved as biblionumber = $biblionumber" if $config->{'verbose'};

    # Add items to the record
    for ( 1..$req->{'noofcopies'} ) {

        my %item = (
            'homebranch'    => $req->{'department'},
            'holdingbranch' => $req->{'department'},
            'itype'         => $req->{'loanperiod'},
        );
        my ($biblionumber, $biblioitemnumber, $itemnumber) = AddItem( \%item, $biblionumber );
        say "Added item = $itemnumber to biblionumber = $biblionumber" if $config->{'verbose'};

    }

    $self->mark_request_as_processed( $req->{'request_id'} );

}

sub get_record {

    my ( $self, $marcorigin, $titleno, $config ) = @_;

    my $record;
    if ( $marcorigin eq 'LIBRIS' ) {
        $record = $self->get_record_from_libris( $titleno, $config );
    } elsif ( $marcorigin eq 'BURK' ) {
        # TODO $record = $self->get_record_from_burk( $titleno );
    } else {
        $record = undef;
    }

    return $record;

}

=head2 get_record_from_libris

  my $record = get_record_from_libris( $titlenumber );

Takes: A titlenumber

Returns: A MARC::Record

=cut

sub get_record_from_libris {

    my ( $self, $titleno, $config ) = @_;

    say "Looking for $titleno in LIBRIS" if $config->{'verbose'};

    my $importer = Catmandu::Importer::SRU->new(
        base => 'http://api.libris.kb.se/sru/libris', # Libris SRU endpoint
        query => "rec.recordIdentifier=$titleno",
        recordSchema => 'marcxml',
        parser => 'marcxml',
    );

    return undef if $importer->count != 1;
    $importer->rewind;

    my $marcxml;
    my $exporter = Catmandu->exporter('MARC', file => \$marcxml, type => "XML" );
    $exporter->add_many($importer);

    if ( $marcxml ) {
        # marc:collection is not closed, for some reason
        $marcxml .= '</marc:collection>';
        say "Found it" if $config->{'verbose'};
    }

    return MARC::Record->new_from_xml( $marcxml );

}

sub mark_request_as_processed {

    my ( $self, $request_id ) = @_;

    my $table = $self->get_qualified_table_name('requests');

    return C4::Context->dbh->do( "UPDATE $table SET processed = 1 WHERE request_id = $request_id" );

}

1;
