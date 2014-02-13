#!/bin/bash

rm -rf static
mkdir -p static
cp -r .git static
cd static
git reset --hard HEAD
./setup.sh
LDFLAGS='-L/usr/local/lib -all-static' \
CPPFLAGS=-I/usr/local/include \
./configure --disable-shared
make test

# vim:ts=2:sw=2:sts=2:et:ft=sh
