#!/usr/bin/env perl

use strict;
use warnings;

use DateTime;

my @ct = ();

while (<>) {
  chomp;
  next if /^\s*#/;
  next if /^\s*$/;
  my @f = split /\s+/, $_, 6;
  die "Malformed line" unless @f == 6;
  push @ct, parse_rule(@f);
}

my $ii = mk_merge_iter(@ct);
while () {
  my $now = time;
  my ( $ts, $verb ) = @{ $ii->() };
  my $then = $ts->epoch;
  if ( $then > $now ) {
    my $wait = $then - $now;
    print "(sleeping $wait seconds)\n";
    sleep $wait;
  }
  my $lt = localtime;
  print "[$lt] $ts: $verb\n";
}

sub mk_merge_iter {
  my @iter = ();

  for my $ii (@_) {
    my $nv = $ii->();
    push @iter, [$nv, $ii];
  }

  return sub {
    @iter = sort { DateTime->compare( $a->[0][0], $b->[0][0] ) } @iter;
    my $nv = $iter[0][0];
    $iter[0][0] = $iter[0][1]->();
    return $nv;
  };
}

sub mk_val_tab {
  my ( $val, $min, $max, $tab ) = @_;

  my ( $base, $int ) = $val =~ m{^(.+)/(\d+)$} ? ( $1, $2 ) : ( $val, 1 );

  my ( $lo, $hi )
   = $base eq '*'              ? ( $min,  $max )
   : $base =~ m{^(\d+)-(\d+)$} ? ( $1,    $2 )
   : $base =~ m{^(\d+)$}       ? ( $base, $base )
   :                             die "Bad range";

  die "Bad range" if $lo < $min || $hi > $max || $lo > $hi;

  # Mark slots in table
  for ( my $i = $lo; $i <= $hi; $i += $int ) {
    $tab->[$i]++;
  }
}

sub mk_field_vals {
  my ( $fld, $min, $max ) = @_;

  my @tab = (0) x $max;

  for my $val ( split /,/, $fld ) {
    mk_val_tab( $val, $min, $max, \@tab );
  }

  my @vals = ();
  for my $i ( 0 .. $#tab ) {
    push @vals, $i if $tab[$i];
  }
  return @vals;
}

sub mk_field_iter {
  my @vals = @_;

  return sub {
    my $nv = shift @vals;
    push @vals, $nv;
    return $nv;
  };
}

sub mk_odo_iter {
  my ( $skip, @iter ) = @_;
  my @state = map { $_->() } @iter;

  my $ii = sub {
    my $pos = shift || 0;
    my $nv = [@state];
    # Odometer increment
    for my $i ( $pos .. $#state ) {
      my $lv = $state[$i];
      $state[$i] = $iter[$i]->();
      last if $state[$i] > $lv;
    }
    return $nv;
  };

  # Advance to skip
  SKIP: while () {
    my $pos = $#state;
    until ( $pos < 0 ) {
      last SKIP if $state[$pos] > $skip->[$pos];
      if ( $state[$pos] < $skip->[$pos] ) {
        $ii->($pos);
        next SKIP;
      }
      $pos--;
    }
  }

  return $ii;
}

sub mk_seq_iter {
  my $nv = shift;
  return sub { $nv++ };
}

sub mk_rule_iter {
  my ( $verb, $days, @iter ) = @_;

  my $nw   = DateTime->now;
  my $skip = [$nw->minute, $nw->hour, $nw->day, $nw->month, $nw->year];
  my $ii   = mk_odo_iter( $skip, @iter, mk_seq_iter( $nw->year ) );

  return sub {
    while () {
      my $nv  = $ii->();
      my $now = DateTime->now;
      my $ts  = eval {
        DateTime->new(
          minute => $nv->[0],
          hour   => $nv->[1],
          day    => $nv->[2],
          month  => $nv->[3],
          year   => $nv->[4]
        );
      };
      next unless $ts;
      next unless $days->{ $ts->day_of_week };
      return [$ts, $verb];
    }
  };
}

sub parse_rule {
  my @f     = @_;
  my @range = ( [0, 59], [0, 23], [1, 31], [1, 12] );
  my $verb  = pop @f;
  my $days  = pop @f;
  my @iter  = ();
  for my $i ( 0 .. $#range ) {
    my @tab = mk_field_vals( $f[$i], @{ $range[$i] } );
    push @iter, mk_field_iter(@tab);
  }
  my %days = map { $_ => 1 } mk_field_vals( $days, 1, 7 );
  return mk_rule_iter( $verb, \%days, @iter );
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

