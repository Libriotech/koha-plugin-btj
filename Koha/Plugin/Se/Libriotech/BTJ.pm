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
use C4::Items qw( AddItem ModItem GetItemsInfo );

use MARC::Record;
use MARC::File::XML;
use Catmandu::Importer::SRU;
use Catmandu::Exporter::MARC;
use CGI qw ( -utf8 );
use Data::Dumper;
use Modern::Perl;

## Required for all plugins
use base qw(Koha::Plugins::Base);

## We will also need to include any Koha libraries we want to access

## Here we set our plugin version
our $VERSION = '0.0.23';

## Here is our metadata, some keys are required, some are optional
our $metadata = {
    name            => 'BTJ import',
    author          => 'Magnus Enger, Libriotech',
    description     => 'Receive aquisitions data from BTJ',
    date_authored   => '2016-10-18',
    date_updated    => '2017-02-06',
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

    my $requests_table = $self->get_qualified_table_name('requests');
    my $result;
    my $end_result = 1;
    $result = C4::Context->dbh->do( "
        CREATE TABLE $requests_table (
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
            account varchar(255),           -- Account: Värde som användaren angav när ordern lades (anslag)
            status int not null default 0,  -- Status: Orderns status (1=Öppen order, 2= levererad, 3= fakturerad, 4=annullerad)
            origindata varchar(255),        -- OriginData: Unikt värde för varje orderrad, om en LINK beställning så kommer den därifrån annars genererar vi ett unikt värde för varje orderrad.
            remote_ip char(16),
            processed tinyint(1) not null default 0,
            added timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP, 
            PRIMARY KEY (request_id)
        ) ENGINE = INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    " );
    $end_result = 0 unless $result;

    my $orders_table = $self->get_qualified_table_name('orders');
    $result = C4::Context->dbh->do( "
        CREATE TABLE $orders_table (
            order_id  int(32) NOT NULL auto_increment, -- Primary key
            author varchar(255),            -- Author: Artikelns författare (om aktuellt).
            title varchar(255),             -- Title: Artikelns titel.
            deliverydate char(32),          -- DeliveryDate: Uppskattat skeppningsdatum.
            orderdate char(32),             -- OrderDate: Orderdatum
            titleno char(32) not null,      -- TitleNo: BurkNummer eller Librisnummer beroende på inställning.
            marcorigin char(12) not null,   -- MarcOrigin: Om BurkNummer (”BTJ”)eller Librisnummer (”LIBRIS”)
            department varchar(255),        -- Department: Värde som användaren angav när ordern lades (avdelning)
            status int not null default 0,  -- Status: Orderns status (1=Öppen order, 2= levererad, 3= fakturerad, 4=annullerad)
            origindata varchar(255),        -- OriginData: Unikt värde för varje orderrad, om en LINK beställning så kommer den därifrån annars genererar vi ett unikt värde för varje orderrad.
            biblionumber int(11) not null,  -- A link to the biblio and biblioitems table, as well as for finding items in the items table
            added timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (order_id)
        ) ENGINE = INNODB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
    " );
    $end_result = 0 unless $result;

    return $end_result;

}

## This method will be run just before the plugin files are deleted
## when a plugin is uninstalled. It is good practice to clean up
## after ourselves!
sub uninstall() {
    my ( $self, $args ) = @_;

    my $requests_table = $self->get_qualified_table_name('requests');
    C4::Context->dbh->do("DROP TABLE $requests_table");

    my $orders_table = $self->get_qualified_table_name('orders');
    C4::Context->dbh->do("DROP TABLE $orders_table");

}

sub tool {

    my ( $self, $args ) = @_;

    my $cgi = $self->{'cgi'};
    my $template;
    if (      $cgi->param('order') ) {
        $template = $self->show_order( $cgi->param('order') );
    } elsif (      $cgi->param('orders') && $cgi->param('orders') eq 'open' ) {
        $template = $self->show_orders(1);
    } elsif ( $cgi->param('orders') && $cgi->param('orders') eq 'delivered' ) {
        $template = $self->show_orders(2);
    } elsif ( $cgi->param('orders') && $cgi->param('orders') eq 'cancelled' ) {
        $template = $self->show_orders(4);
    } else {
        $template = $self->show_orders();
    }

    print $cgi->header({
        -type     => 'text/html',
        -charset  => 'UTF-8',
        -encoding => "UTF-8"
    });
    print $template->output();

}

sub show_order {

    my ( $self, $order_id ) = @_;
    my $template = $self->get_template({ file => 'show-order.tt' });

    my $dbh = C4::Context->dbh;

    my $order_table = $self->get_qualified_table_name('orders');
    my $order_sth   = $dbh->prepare("SELECT * FROM $order_table WHERE order_id = $order_id");
    $order_sth->execute();
    my $order = $order_sth->fetchrow_hashref();

    my $requests_table = $self->get_qualified_table_name('requests');
    my $requests_sth = $dbh->prepare("SELECT * FROM $requests_table WHERE origindata = '$order->{'origindata'}';");
    $requests_sth->execute();
    my $requests = $requests_sth->fetchall_arrayref({});

    $template->param(
        'order'   => $order,
        'requests' => $requests,
    );

    return $template;

}

sub show_orders {

    my ( $self, $status ) = @_;
    my $template = $self->get_template({ file => 'show-orders.tt' });

    my $dbh = C4::Context->dbh;
    my $table = $self->get_qualified_table_name('orders');
    my $sth;
    if ( $status && $status > 0 ) {
        $sth   = $dbh->prepare("SELECT * FROM $table WHERE status = $status ORDER BY order_id DESC");
    } else {
        $sth   = $dbh->prepare("SELECT * FROM $table ORDER BY order_id DESC LIMIT 10");
        $status = 0;
    }
    $sth->execute();
    my $orders = $sth->fetchall_hashref('origindata');

    $template->param(
        'orders' => $orders,
        'status' => $status,
    );

    return $template;

}

=head2 update_biblio()

  $btj->update_biblio( $request, $config );

If there is no biblio, add it. If there is a biblio, update it. 

Use data from the request if there is no TitleNo, or get the record from an 
external source if there is a TitleNo.

=cut

sub update_biblio {

    my ( $self, $req, $config ) = @_;

    my $dbh = C4::Context->dbh;

    # Check if there is an order for this request
    my $order = $self->get_order( $req->{'origindata'} );
    unless ( $order ) {

        say "No saved order found, going to save it now" if $config->{'debug'};

        # Record this as a new order in the 'orders' table
        my $orders_table = $self->get_qualified_table_name('orders');
        my $query = "INSERT INTO $orders_table SET
            author = ?,
            title = ?,
            deliverydate = ?,
            orderdate = ?,
            titleno = ?,
            marcorigin = ?,
            department = ?,
            status = ?,
            origindata = ?";
        my @values = (
            $req->{'author'},
            $req->{'title'},
            $req->{'deliverydate'},
            $req->{'orderdate'},
            $req->{'titleno'},
            $req->{'marcorigin'},
            $req->{'department'},
            $req->{'status'},
            $req->{'origindata'},
        );
        if ( $dbh->do( $query, undef, @values ) ) {
            # And retrieve the data again
            $order = $self->get_order( $req->{'origindata'} );
        } else {
            say "Could not save the order";
            return;
        }

    } else {
        say "Found an existing order" if $config->{'debug'};
        say Dumper $order;
    }

    # Get the record
    my $record;
    if ( $req->{'marcorigin'} && $req->{'marcorigin'} ne '' && $req->{'titleno'} && $req->{'titleno'} ne '' ) {
        $record = $self->get_record( $req->{'marcorigin'}, $req->{'titleno'}, $config );
    }
    unless ( $record ) {
        say "No record found, going to create one (marcorigin=$req->{'marcorigin'} titleno=$req->{'titleno'})" if $config->{'debug'};
        $record = _create_record_from_request( $req );
    }
    say Dumper $record if $config->{'debug'};

    if ( $order->{'biblionumber'} ) {

        # TODO Update the record in Koha
        if ( ModBiblio( $record, $order->{'biblionumber'}, '' ) ) {
            say "biblionumber=$order->{'biblionumber'} was updated" if $config->{'debug'};
        } else {
            say "biblionumber=$order->{'biblionumber'} was NOT updated" if $config->{'debug'};
        }

    } else {

        # Add record and items to Koha
        # FIXME Should frameworkcode be configurable?
        my ( $biblionumber, $biblioitemnumber ) = AddBiblio( $record, '' );
        say "Saved as biblionumber = $biblionumber" if $config->{'verbose'};

        # TODO Add the biblionumber to the order
        $self->update_order_with_biblionumber( $order->{'order_id'}, $biblionumber );

        # Add items to the record
        for ( 1..$req->{'noofcopies'} ) {

            # Make sure homebranch is non empty
            my $homebranch;
            if ( $config->{'customerno2library'}->{ $req->{'customerno'} } ) {
                $homebranch = $config->{'customerno2library'}->{ $req->{'customerno'} };
            } else {
                $homebranch = $config->{'on_order_branch'};
            }

            my %item = (
                'homebranch'          => $homebranch,
                'holdingbranch'       => $config->{'on_order_branch'},
                'itype'               => $config->{'on_order_itemtype'},
                'itemcallnumber'      => $req->{'shelfmarc'}, # classification??
                'itemnotes_nonpublic' => $config->{'deliverydate_prefix'} . $req->{'deliverydate'} . $config->{'deliverydate_postfix'},
                'notforloan'          => -1, # Ordered
                'location'            => $config->{'loc_open_order'},
            );
            my ($biblionumber, $biblioitemnumber, $itemnumber) = AddItem( \%item, $biblionumber );
            say "Added item = $itemnumber to biblionumber = $biblionumber" if $config->{'verbose'};

        }

    }

}

=head2 process_open_order

Status = 1

=cut

sub process_open_order {

    my ( $self, $req, $config ) = @_;

    return unless $req->{'status'} == 1;

    # Find the order
    my $order = $self->get_order( $req->{'origindata'} );

    # Update the order with info from the request
    $self->update_order_from_request( $order->{'order_id'}, $req );

    # Update the order, 2 means "open"
    $self->update_order_status( $order->{'order_id'}, 1 );

    # Mark the request as done
    $self->mark_request_as_processed( $req->{'request_id'} );

}

=head2 process_delivered_order

Status = 2

=cut

sub process_delivered_order {

    my ( $self, $req, $config ) = @_;

    # Find the order
    my $order = $self->get_order( $req->{'origindata'} );
    say "Order: $req->{'origindata'}, order_id: $order->{'order_id'}, biblionumber: $order->{'biblionumber'}" if $config->{'verbose'};

    # Find the items and update them
    my @items = GetItemsInfo( $order->{'biblionumber'} );
    foreach my $item ( @items ) {

        ModItem( { location => $config->{'loc_delivered_order'} }, $order->{'biblionumber'}, $item->{'itemnumber'} );
        say "Itemnumber $item->{'itemnumber'} was updated";

    }

    # Update the order with info from the request
    $self->update_order_from_request( $order->{'order_id'}, $req );

    # Update the order, 2 means "delivered"
    $self->update_order_status( $order->{'order_id'}, 2 );

    # Mark the request as done
    $self->mark_request_as_processed( $req->{'request_id'} );

}

=head2 process_cancelled_order

Status = 4

=cut

sub process_cancelled_order {

    my ( $self, $req, $config ) = @_;

    # Find the order
    my $order = $self->get_order( $req->{'origindata'} );
    say "Order: $req->{'origindata'}, order_id: $order->{'order_id'}, biblionumber: $order->{'biblionumber'}" if $config->{'verbose'};

    # Find the items and update them
    my @items = GetItemsInfo( $order->{'biblionumber'} );
    foreach my $item ( @items ) {

        ModItem( { location => '', notforloan => $config->{'not_loan_cancelled'} }, $order->{'biblionumber'}, $item->{'itemnumber'} );
        say "Itemnumber $item->{'itemnumber'} was updated";

    }

    # Update the order with info from the request
    $self->update_order_from_request( $order->{'order_id'}, $req );

    # Update the order status, 4 means "cancelled"
    $self->update_order_status( $order->{'order_id'}, 4 );

    # Mark the request as done
    $self->mark_request_as_processed( $req->{'request_id'} );

}

=head2 get_record

=cut

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

=head2 get_order

=cut

sub get_order {

    my ( $self, $origindata ) = @_;

    my $dbh = C4::Context->dbh;

    my $orders_table = $self->get_qualified_table_name('orders');
    my $query = "SELECT * FROM $orders_table WHERE origindata = '$origindata';";
    my $sth = $dbh->prepare($query);
    $sth->execute();
    return $sth->fetchrow_hashref();

}

=head2 update_order_from_request

=cut

sub update_order_from_request {

    my ( $self, $order_id, $req ) = @_;

    my $dbh = C4::Context->dbh;

    my $orders_table = $self->get_qualified_table_name('orders');
    my $query = "UPDATE $orders_table SET
        author = ?,
        title = ?,
        deliverydate = ?,
        orderdate = ?,
        titleno = ?,
        marcorigin = ?,
        department = ?
        WHERE order_id = ?";
    my @values = (
        $req->{'author'},
        $req->{'title'},
        $req->{'deliverydate'},
        $req->{'orderdate'},
        $req->{'titleno'},
        $req->{'marcorigin'},
        $req->{'department'},
        $order_id,
    );
    return $dbh->do( $query, undef, @values );

}

=head2 get_record_from_libris

  my $record = get_record_from_libris( $titlenumber, $config );

Takes: A titlenumber

Returns: A MARC::Record

=cut

sub get_record_from_libris {

    my ( $self, $titleno, $config ) = @_;

    say "Looking for '$titleno' in LIBRIS" if $config->{'verbose'};

    my $importer = Catmandu::Importer::SRU->new(
        base => 'http://api.libris.kb.se/sru/libris', # Libris SRU endpoint
        query => "rec.recordIdentifier=$titleno",
        recordSchema => 'marcxml',
        parser => 'marcxml',
    );

    my $marcxml;
    my $exporter = Catmandu->exporter('MARC', file => \$marcxml, type => "XML" );
    $exporter->add_many($importer);

    if ( $marcxml ) {
       # marc:collection is not closed, for some reason
       $marcxml .= '</marc:collection>';
       say "Found it" if $config->{'verbose'};
       say $marcxml if $config->{'debug'};
       my $record = MARC::Record->new_from_xml( $marcxml, 'UTF-8' );
       $record->encoding( 'UTF-8' );
       return $record;
    } else {
        return undef;
    }

}

sub mark_request_as_processed {

    my ( $self, $request_id ) = @_;

    my $table = $self->get_qualified_table_name('requests');

    return C4::Context->dbh->do( "UPDATE $table SET processed = 1 WHERE request_id = $request_id" );

}

sub update_order_status {

    my ( $self, $order_id, $status ) = @_;

    my $orders_table = $self->get_qualified_table_name('orders');

    return C4::Context->dbh->do( "UPDATE $orders_table SET status = $status WHERE order_id = $order_id" );

}

sub update_order_with_biblionumber {

    my ( $self, $order_id, $biblionumber ) = @_;

    my $orders_table = $self->get_qualified_table_name('orders');

    return C4::Context->dbh->do( "UPDATE $orders_table SET biblionumber = $biblionumber WHERE order_id = $order_id" );

}

=head2 _send_response()

  $btj->send_response( $message );

Takes a text string and sends it off as an XML formatted response.

Returns: Nothing.

=cut

sub send_response {

    my ( $self, $msg ) = @_;
    my $cgi  = new CGI;

    print $cgi->header({
        -type     => 'text/xml',
        -charset  => 'UTF-8',
        -encoding => "UTF-8"
    });
    say '<?xml version="1.0" encoding="UTF-8"?>';
    say '<status>';
    say "<value>$msg</value>";
    say '</status>';

    exit;

}

=head1 INTERNAL SUBROUTINES

=head2 _create_record_from_request()

  my $record = _create_record_from_request( $request );

Takes: A request.

Returns: A minimal MARC::Record, with title, author and ISBN from the request.

=cut

sub _create_record_from_request {

    my ( $req ) = @_;

    my $record = MARC::Record->new();
    $record->encoding( 'UTF-8' );

    my $titleno    = MARC::Field->new( '001', $req->{'titleno'} );
    my $marcorigin = MARC::Field->new( '003', $req->{'marcorigin'} );
    $record->insert_fields_ordered( $titleno, $marcorigin );

    # Create an SIBN field
    my $isbn = MARC::Field->new(
        '020', '', '',
        a => $req->{'isbn'},
    );
    $record->insert_fields_ordered( $isbn );

    # Create an author field
    my $author = MARC::Field->new(
        '100', '', '',
        a => $req->{'author'},
    );
    $record->insert_fields_ordered( $author );

    ## create a title field.
    my $title = MARC::Field->new(
        '245', '', '',
        a => $req->{'title'},
    );
    $record->insert_fields_ordered( $title );

    return $record;

}

1;
