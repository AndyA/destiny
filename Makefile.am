DIST_SUBDIRS = m4 t

SUBDIRS = . t

ACLOCAL_AMFLAGS = -I m4

lib_LTLIBRARIES = libdestiny.la

bin_PROGRAMS = destiny

bin_SCRIPTS = scripts/destiny-diff

libdestiny_la_SOURCES = \
	digest.c digest.h \
	filename.c filename.h \
	find.c find.h \
	log.c log.h \
	manifest.c manifest.h \
	md5.c md5.h \
	utils.c utils.h

libdestiny_la_LDFLAGS = -avoid-version

destiny_SOURCES = main.c
destiny_LDADD = libdestiny.la

test: all
	cd t && $(MAKE) test

