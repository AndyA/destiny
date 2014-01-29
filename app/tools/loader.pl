#!/usr/bin/env perl

use strict;
use warnings;

use DBI;
use Data::Dumper;
use Getopt::Long;
use JSON;
use Path::Class;
use Sys::Hostname;

use constant DB    => 'destiny';
use constant HOST  => 'localhost';
use constant USER  => 'root';
use constant PASS  => '';
use constant BATCH => 500;

$| = 1;

my %O = (
  host => undef,
  path => undef,
);

my %INSERT = ();    # defer_insert cache

GetOptions(
  'host:s' => \$O{host},
  'path:s' => \$O{path},
) or die;

die "If path is specified only one file may be processed\n"
 if defined $O{path} && @ARGV > 1;

$O{host} = hostname unless defined $O{host};

my $dbh = dbh(DB);

for my $mf (@ARGV) {
  print "Loading $mf\n";
  my $manifest    = load_manifest($mf);
  my $path        = defined $O{path} ? $O{path} : $mf;
  my $host_id     = vivify( $dbh, 'host', { name => $O{host} } );
  my $manifest_id = vivify(
    $dbh,
    'manifest',
    { host_id => $host_id,
      path    => $path
    }
  );

  print "Importing data\n";
  insert( $dbh, 'import', { when => time, manifest_id => $manifest_id } );
  my $import_id = $dbh->last_insert_id( undef, undef, 'import', undef );
  my $batch     = 0;
  my $done      = 0;
  for my $rec (@$manifest) {
    if ( ++$batch >= BATCH ) {
      flush_pending($dbh);
      $done += $batch;
      $batch = 0;
      printf "\r%6.2f%%", 100 * $done / @$manifest;
    }
    my %nr = %$rec;
    $nr{$_} = hex $nr{$_} for 'dev', 'ino';
    $nr{$_} = oct $nr{$_} for 'mode';
    $nr{import_id} = $import_id;

    defer_insert( $dbh, 'object', \%nr );
  }
  flush_pending($dbh);

  $dbh->do( 'UPDATE `manifest` SET `current_id` = ? WHERE `id` = ?',
    {}, $import_id, $manifest_id );

  printf "\r%6.2f%%\n", 100;
  print "Purging previous imports\n";
  cleanup( $dbh, $manifest_id, $import_id );

}

$dbh->disconnect;

sub cleanup {
  my ( $dbh, $manifest_id, $import_id ) = @_;
  my ( $sql, @bind ) = make_select(
    'import',
    { manifest_id => $manifest_id,
      id          => ['<>', $import_id],
    },
    ['id']
  );
  my @ids = @{ $dbh->selectcol_arrayref( $sql, {}, @bind ) };
  if (@ids) {
    del( $dbh, 'object', { import_id => ['IN', \@ids] } );
    del( $dbh, 'import', { id        => ['IN', \@ids] } );
  }
}

sub del {
  my ( $dbh, $tbl, $sel ) = @_;
  my ( $where, @bind ) = make_where($sel);
  $dbh->do( "DELETE FROM `$tbl` WHERE $where", {}, @bind );
}

sub load_manifest { JSON->new->decode( file(shift)->slurp ) }

sub dbh {
  my $db = shift;
  return DBI->connect(
    sprintf( 'DBI:mysql:database=%s;host=%s', $db, HOST ),
    USER, PASS, { RaiseError => 1 } );
}

sub show_sql {
  my ( $sql, @bind ) = @_;
  my $next = sub {
    my $val = shift @bind;
    return 'NULL' unless defined $val;
    return $val if $val =~ /^\d+(?:\.\d+)?$/;
    $val =~ s/\\/\\\\/g;
    $val =~ s/\n/\\n/g;
    $val =~ s/\t/\\t/g;
    return "'$val'";
  };
  $sql =~ s/\?/$next->()/eg;
  return $sql;
}

sub vivify {
  my ( $dbh, $tbl, $rec ) = @_;

  my ( $sql, @bind ) = make_select( $tbl, $rec, ['id'] );
  my $res = ( $dbh->selectcol_arrayref( $sql, {}, @bind ) )->[0];

  return $res if defined $res;

  insert( $dbh, $tbl, $rec );
  return $dbh->last_insert_id( undef, undef, $tbl, undef );
}

sub extended_insert {
  my ( $dbh, $ins ) = @_;
  for my $tbl ( keys %$ins ) {
    for my $flds ( keys $ins->{$tbl} ) {
      my @k = split /:/, $flds;
      my @sql
       = ( "INSERT INTO `$tbl` (", join( ', ', map "`$_`", @k ), ") VALUES " );
      my $vc = '(' . join( ', ', map '?', @k ) . ')';
      my @data = @{ $ins->{$tbl}{$flds} };
      push @sql, join ', ', ($vc) x @data;
      my $sql = join '', @sql;
      my @bind = map @$_, @data;
      #      print show_sql( $sql, @bind ), "\n";
      my $sth = $dbh->prepare($sql);
      $sth->execute(@bind);
    }
  }
}

sub insert {
  my ( $dbh, $tbl, $rec ) = @_;
  my @k = sort keys %$rec;
  my $ins = { $tbl => { join( ':', @k ) => [[@{$rec}{@k}]] } };
  extended_insert( $dbh, $ins );
}

sub make_where {
  my $sel = shift;
  my ( @bind, @term );
  for my $k ( sort keys %$sel ) {
    my $v = $sel->{$k};
    my ( $op, $vv ) = 'ARRAY' eq ref $v ? @$v : ( '=', $v );
    if ( 'ARRAY' eq ref $vv ) {
      push @term, "`$k` $op (" . join( ', ', map '?', @$vv ) . ")";
      push @bind, @$vv;
    }
    else {
      push @term, "`$k` $op ?";
      push @bind, $vv;
    }
  }
  @term = ('TRUE') unless @term;
  return ( join( ' AND ', @term ), @bind );
}

sub make_select {
  my ( $tbl, $sel, $cols, $ord ) = @_;

  my $limit = delete $sel->{LIMIT};
  my ( $where, @bind ) = make_where($sel);

  my @sql = (
    'SELECT',
    ( $cols ? join ', ', map "`$_`", @$cols : '*' ),
    "FROM `$tbl` WHERE ", $where
  );

  if ($ord) {
    push @sql, "ORDER BY", join ', ',
     map { /^-(.+)/ ? "`$1` DESC" : "`$_` ASC" } @$ord;
  }

  if ( defined $limit ) {
    push @sql,  'LIMIT ?';
    push @bind, $limit;
  }

  return ( join( ' ', @sql ), @bind );
}

sub execute_select {
  my ( $dbh, $tbl, $sel, $cols, $ord ) = @_;

  my ( $sql, @bind ) = make_select( $tbl, $sel, $cols, $ord );
  #  print show_sql( $sql, @bind ), "\n";
  my $sth = $dbh->prepare($sql);
  $sth->execute(@bind);
  return $sth;
}

sub flush_pending {
  my $dbh = shift;
  my $ins = {%INSERT};
  %INSERT = ();
  $dbh->do('START TRANSACTION');
  eval { extended_insert( $dbh, $ins ) };
  if ( my $err = $@ ) {
    $dbh->do('ROLLBACK');
    die $err;
  }
  $dbh->do('COMMIT');
}

sub defer_insert {
  my ( $dbh, $tbl, $rec ) = @_;

  my @k = sort keys %$rec;
  my $k = join ':', @k;
  push @{ $INSERT{$tbl}{$k} }, [@{$rec}{@k}];
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

