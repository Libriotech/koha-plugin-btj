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

=pod

=head1 pack.pl

Package up the relevant parts as a .kpz Koha plugin file.

=head1 USAGE

  sudo koha-shell -c "perl pack.pl" <kohainstance>

=head1 PREREQUISITES

=head2 zip

  sudo apt-get install zip

=cut

use Modern::Perl;
use Koha::Plugin::Se::Libriotech::BTJ;
my $version  = $Koha::Plugin::Se::Libriotech::BTJ::VERSION;
my $filename = "koha-plugin-btj-$version.kpz";

say `zip -r $filename Koha/`;

if ( -f $filename ) {
    say "$filename created";
} else {
    say "Oooops, something went wrong!";
}
