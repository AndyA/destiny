#!/usr/bin/env perl

use strict;
use warnings;

use Digest::MD5 qw( md5_hex );

my @SRC = (
  '', '0', '1', 'And now for something different',
  map { 'x' x $_ } ( 1..129 )
);

for my $src (@SRC) {
  my $md5 = md5_hex($src);
  print qq{  { "$md5", "$src" },\n};
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

