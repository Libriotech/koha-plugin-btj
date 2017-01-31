#!/usr/bin/perl

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

use Koha::Plugins;
use Koha::Plugin::Se::Libriotech::BTJ;
use C4::Auth;
use C4::Output;
use C4::Debug;
use C4::Context;

use CGI qw ( -utf8 );
use Modern::Perl;

my $cgi  = new CGI;
my $time = time();
my $btj  = Koha::Plugin::Se::Libriotech::BTJ->new;

# Check that we have some mandatory arguments
my $missing = _all_mandatory_args( $cgi, 'OriginData', 'SupplierCode' );
if ( $missing ne 'ok' ) {
    print $cgi->header({
        -type     => 'text/plain',
        -charset  => 'UTF-8',
        -encoding => "UTF-8"
    });
    say "Missing mandatory argument: $missing";
    exit;
}

# Dump the CGI request to a file for debugging
open ( my $out_fh, ">>", "/tmp/btj-cgi-$time.txt" ) || die "Can't open test.txt: $!";
$cgi->save( $out_fh );
close( $out_fh );

# Test URL
# http://localhost:2201/btj.pl?SupplierCode=BTJ&CustomerNoCustomer=123&Author=Name,+No&Title=Some+title&Isbn=1234567890123&Classification=SAB&PurchaseNote=For+the+staff&ArticleNo=1234&Price=345&Currency=SEK&DeliveryDate=2016-11-11&InfoNote=plastad&NoOfCopies=3&OrderDate=2016-10-10&TitleNo=636970&MarcOrigin=LIBRIS&Department=CPL&LocalShelf=Fiction&LoanPeriod=28&ShelfMarc=SAB+123&AccountV=123&Status=1&OriginData=017c13cd96a3bcf000d9e2e79eecd7d7

my %data = (
    'suppliercode'   => $cgi->param( 'SupplierCode' ) || '',
    'customerno'     => $cgi->param( 'CustomerNoCustomer' ) || '',
    'author'         => $cgi->param( 'Author' ) || '',
    'title'          => $cgi->param( 'Title' ) || '',
    'isbn'           => $cgi->param( 'Isbn' ) || '',
    'classification' => $cgi->param( 'Classification' ) || '',
    'purchasenote'   => $cgi->param( 'PurchaseNote' ) || '',
    'articleno'      => $cgi->param( 'ArticleNo' ) || '',
    'price'          => $cgi->param( 'Price' ) || '',
    'currency'       => $cgi->param( 'Currency' ) || '',
    'deliverydate'   => $cgi->param( 'DeliveryDate' ) || '',
    'infonote'       => $cgi->param( 'InfoNote' ) || '',
    'noofcopies'     => $cgi->param( 'NoOfCopies' ) || '',
    'orderdate'      => $cgi->param( 'OrderDate' ) || '',
    'titleno'        => $cgi->param( 'TitleNo' ) || '',
    'marcorigin'     => $cgi->param( 'MarcOrigin' ) || '',
    'department'     => $cgi->param( 'Department' ) || '',
    'localshelf'     => $cgi->param( 'LocalShelf' ) || '',
    'loanperiod'     => $cgi->param( 'LoanPeriod' ) || '',
    'shelfmarc'      => $cgi->param( 'ShelfMarc' ) || '',
    'accountv'       => $cgi->param( 'AccountV' ) || '',
    'status'         => $cgi->param( 'Status' ) || '',
    'origindata'     => $cgi->param( 'OriginData' ) || '',
    'remote_ip'      => $cgi->remote_addr(),
);

# Save everything in the database
my $table = $btj->get_qualified_table_name('requests');
my $dbh = C4::Context->dbh;
my $query = "INSERT INTO $table SET ";
my @values;
my $counter = 0;
my $max = scalar keys %data;
while( my( $key, $value ) = each %data ) {
    $counter++;
    $query .= "$key = ?";
    if ( $counter != $max ) {
        $query .= ", "
    } else {
        $query .= ";"
    }
    push @values, $value;
}

my $ret = $dbh->do( $query, undef, @values );
if ( $ret ) {
    print $cgi->header({
        -type     => 'text/xml',
        -charset  => 'UTF-8',
        -encoding => "UTF-8"
    });
    say '<status value="ok"/>';
} else {
    say "Could not save the request.";
}

sub _all_mandatory_args {

    my ( $cgi, @args ) = @_;

    foreach my $arg ( @args ) {
        unless ( $cgi->param( $arg ) && $cgi->param( $arg ) ne '' ) {
            return $arg;
        }
    }

    return 'ok';

}
