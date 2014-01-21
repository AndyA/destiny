DIST_SUBDIRS = m4 t

SUBDIRS = . t

ACLOCAL_AMFLAGS = -I m4

lib_LTLIBRARIES = libdestiny.la

bin_PROGRAMS = destiny

libdestiny_la_SOURCES = \
	digest.c digest.h \
	filename.c filename.h \
	manifest.c manifest.h \
	utils.c utils.h \
	md5.c md5.h

libdestiny_la_LDFLAGS = -avoid-version

destiny_SOURCES = main.c
destiny_LDADD = libdestiny.la

test: all
	cd t && $(MAKE) test

