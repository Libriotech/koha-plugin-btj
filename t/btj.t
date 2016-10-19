#!/usr/bin/perl

# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

# This Koha test module uses Test::MockModule to get around the need for known
# contents in the authority file by returning a single known authority record
# for every call to SearchAuthorities

use Modern::Perl;
use Test::More;

use_ok( 'Koha::Plugin::Se::Libriotech::BTJ' );

done_testing();
