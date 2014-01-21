#!/usr/bin/env perl

use strict;
use warnings;

use Digest::MD5 qw( md5_hex );

my @SRC = (
  '', '0', '1', 'And now for something different',
  'x' x 1, 'x' x 2, 'x' x 4, 'x' x 8, 'x' x 16, 'x' x 32, 'x' x 64,
  'x' x 128,
  'x' x 3, 'x' x 7, 'x' x 15, 'x' x 31, 'x' x 63,
  'x' x 127,
  'x' x 5, 'x' x 9, 'x' x 17, 'x' x 33, 'x' x 65,
  'x' x 129,
);

for my $src (@SRC) {
  my $md5 = md5_hex($src);
  print qq{  { "$md5", "$src" },\n};
}

# vim:ts=2:sw=2:sts=2:et:ft=perl

