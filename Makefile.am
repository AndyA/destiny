DIST_SUBDIRS = m4 t

SUBDIRS = . t

ACLOCAL_AMFLAGS = -I m4

lib_LTLIBRARIES = libdestiny.la

include_HEADERS = destiny.h

bin_PROGRAMS = destiny

libdestiny_la_SOURCES = \
	destiny.c destiny.h md5.c md5.h

libdestiny_la_LDFLAGS = -avoid-version

destiny_SOURCES = main.c utils.c
destiny_LDADD = libdestiny.la

test: all
	cd t && $(MAKE) test

