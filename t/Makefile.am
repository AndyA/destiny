TESTBIN = basic md5

noinst_PROGRAMS = wrap $(TESTBIN)

noinst_LTLIBRARIES = libtest-support.la

libtest_support_la_SOURCES = tap.c tap.h
libtest_support_la_LDFLAGS = -static

LDADD = libtest-support.la ../libdestiny.la

wrap_LDADD =
wrap_LDFLAGS =
wrap_CFLAGS =

md5.c: md5.data

md5.data: md5gen.pl
	perl md5gen.pl > md5.data

test: $(TESTBIN)
	prove -e ./wrap $(TESTBIN)

valgrind: $(TESTBIN)
	prove -e 'valgrind -q' $(addprefix ./,$(TESTBIN))
