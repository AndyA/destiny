TESTBIN = basic

noinst_PROGRAMS = wrap $(TESTBIN)

noinst_LTLIBRARIES = libtest-support.la

libtest_support_la_SOURCES = tap.c tap.h
libtest_support_la_LDFLAGS = -static

LDADD = libtest-support.la ../libdestiny.la

wrap_LDADD =
wrap_LDFLAGS =
wrap_CFLAGS =

test: $(TESTBIN)
	prove -e ./wrap $(TESTBIN)

valgrind: $(TESTBIN)
	prove -e 'valgrind -q' $(addprefix ./,$(TESTBIN))
