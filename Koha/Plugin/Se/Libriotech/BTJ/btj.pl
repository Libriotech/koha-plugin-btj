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

use Modern::Perl;

use CGI qw ( -utf8 );

use Koha::Plugins;
use C4::Auth;
use C4::Output;
use C4::Debug;
use C4::Context;

my $cgi  = new CGI;
my $time = time();

open ( my $out_fh, ">>", "/tmp/btj-cgi-$time.txt" ) || die "Can't open test.txt: $!";
$cgi->save( $out_fh );
close( $out_fh );

print $cgi->header(
    {
        -type     => 'text/html',
        -charset  => 'UTF-8',
        -encoding => "UTF-8"
    }
);

say $time;
