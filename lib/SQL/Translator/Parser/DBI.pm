package SQL::Translator::Parser::DBI;

# -------------------------------------------------------------------
# $Id: DBI.pm,v 1.1 2003-10-03 00:21:41 kycl4rk Exp $
# -------------------------------------------------------------------
# Copyright (C) 2003 Ken Y. Clark <kclark@cpan.org>,
#                    darren chamberlain <darren@cpan.org>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; version 2.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
# 02111-1307  USA
# -------------------------------------------------------------------

=head1 NAME

SQL::Translator::Parser::DBI - "parser" for DBI handles

=head1 SYNOPSIS

  use DBI;
  use SQL::Translator;

  my $dbh = DBI->connect(...);

  my $translator  =  SQL::Translator->new(
      parser      => 'DBI',
      dbh         => $dbh,
  );

Or:

  use SQL::Translator;

  my $translator  =  SQL::Translator->new(
      parser      => 'DBI',
      dsn         => 'dbi:mysql:FOO',
      db_user     => 'guest',
      db_password => 'password',
  );

=head1 DESCRIPTION

This parser accepts an open database handle (or the arguments to create 
one) and queries the database directly for the information.  The correct
SQL::Translator::Parser::DBI class is determined automatically by 
inspecting $dbh->{'Driver'}{'Name'}.

The following are acceptable arguments:

=over

=item * dbh

An open DBI database handle.

=item * dsn

The DSN to use for connecting to a database.

=item * db_user

The user name to use for connecting to a database.

=item * db_password

The password to use for connecting to a database.

=back

=cut

# -------------------------------------------------------------------

use strict;
use DBI;
use vars qw($VERSION @EXPORT);
$VERSION = sprintf "%d.%02d", q$Revision: 1.1 $ =~ /(\d+)\.(\d+)/;

use constant DRIVERS => {
    sqlite => 'SQLite',
};

use Exporter;
use SQL::Translator::Utils qw(debug normalize_name);
use SQL::Translator::Parser::DBI::SQLite;

use base qw(Exporter);
@EXPORT = qw(parse);

#
# Passed a SQL::Translator instance and a string containing the data
#
sub parse {
    my ( $tr, $data ) = @_;

    $tr->debug( "in DBI\n" );
    my $args          = $tr->parser_args;
    my $dbh           = $args->{'dbh'};
    my $dsn           = $args->{'dsn'};
    my $db_user       = $args->{'db_user'};
    my $db_password   = $args->{'db_password'};

    unless ( $dbh ) {
        die 'No DSN' unless $dsn;
        $dbh = DBI->connect( $dsn, $db_user, $db_password, {RaiseError=>1} );
    }

    die 'No database handle' unless defined $dbh;

    my $db_type = $dbh->{'Driver'}{'Name'} or die 'Cannot determine DBI type';
    my $driver  = DRIVERS->{ lc $db_type } or die "$db_type not supported";
    my $pkg     = "SQL::Translator::Parser::DBI::$driver";
    my $sub     = $pkg.'::parse';

    $tr->debug( "Calling sub '$sub'\n" );

#    $tr->load( $pkg );

    {
        no strict 'refs';
        &{ $sub }( $tr, $dbh ) or die "No result from $pkg";
    }

    return 1;
}

1;

# -------------------------------------------------------------------
=pod

=head1 AUTHOR

Ken Y. Clark E<lt>kclark@cpan.orgE<gt>.

=head1 SEE ALSO

DBI.

=cut
