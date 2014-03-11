/* filename.c */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <unistd.h>

#include "tap.h"
#include "filename.h"

#define OK1( fn, p1, fmt )                                \
  static int                                              \
  fn ## _ok( p1, const char *want, const char *msg ) {    \
    char *got = non_null( fn_ ## fn( a1 ) );        \
    int r = !strcmp( got, want );                         \
    ok( r, # fn ": %s (" fmt " -> %s)", msg, a1, want );  \
    if ( !r ) {                                           \
      diag( " got: %s", got );                            \
      diag( "want: %s", want );                           \
    }                                                     \
    free( got );                                          \
    return r;                                             \
  }

#define OK2( fn, p1, p2, fmt )                               \
  static int                                                 \
  fn ## _ok( p1, p2, const char *want, const char *msg ) {   \
    char *got = non_null( fn_ ## fn( a1, a2 ) );       \
    int r = !strcmp( got, want );                            \
    ok( r, # fn ": %s (" fmt " -> %s)", msg, a1, a2, want ); \
    if ( !r ) {                                              \
      diag( " got: %s", got );                               \
      diag( "want: %s", want );                              \
    }                                                        \
    free( got );                                             \
    return r;                                                \
  }

static char *non_null(char *s) {
  if (s) return s;
  s = malloc(5);
  if (!s) die("Malloc failed");
  memcpy(s, "NULL", 5);
  return s;
}

OK1(tidy, const char *a1, "%s");
OK2(rel2abs, const char *a1, const char *a2, "%s, %s");
OK2(rel2abs_file, const char *a1, const char *a2, "%s, %s");
OK2(abs2rel, const char *a1, const char *a2, "%s, %s");
OK2(abs2rel_file, const char *a1, const char *a2, "%s, %s");
OK2(splice, const char *a1, const char *a2, "%s, %s");
OK2(temp, const char *a1, const char *a2, "%s, %s");

static int tidy_nop_ok(const char *inout) {
  return tidy_ok(inout, inout, "tidy is nop");
}

static void test_001(void) {
  ok(fn_is_url("http://example.com"), "is url");
  ok(!fn_is_url("/usr/local"), "is file");
  ok(!fn_is_url("http/example.com"), "is file");

  ok(fn_is_abs("/usr/local"), "is abs");
  ok(!fn_is_abs("http/example.com"), "is relative");
}

static void test_002(void) {
  tidy_nop_ok("nothing/to/see/here");
  tidy_nop_ok(".strange./.but./.true.");
  tidy_nop_ok("..stranger../..but../..still../..true../.../...");

  tidy_ok("//usr///local//bin/foo", "/usr/local/bin/foo",
          "extra slashes");

  tidy_ok("/", "/", "root");
  tidy_ok("/../", "/", "root");
  tidy_ok("./", "./", "canonical 'here'");
  tidy_ok("././", "./", "tidy 'here'");
  tidy_ok("/usr/./local/.//././bin/.", "/usr/local/bin", "lots of dots");

  tidy_ok("../../foo/bar", "../../foo/bar", "legitimate ups");
  tidy_ok("../foo/../bar", "../bar", "down, up");
  tidy_ok("../foo/baz/../../bar", "../bar", "multi down, up");
  tidy_ok("/tmp/../", "/", "root");
  tidy_ok("/.", "/.", "slashdot");
  tidy_ok("foo/.", "foo", "trailing");
  tidy_ok("/../tmp", "/tmp", "silly root up");
  tidy_ok("foo/..", ".", "degenerate special case");

  tidy_ok(".//../foo2/baz33/../bim444//../.././bar", "../bar",
          "pointless");
}

static void test_003(void) {
  char cwd[MAXPATHLEN];

  getcwd(cwd, sizeof(cwd));

  {
    char want[MAXPATHLEN];
    strcpy(want, cwd);
    strcat(want, "/foo");

    rel2abs_ok("bar/../foo", NULL, want, "abs relative to cwd");
    rel2abs_ok("../foo", "bar", want, "abs relative to relative");
  }

  rel2abs_ok("/", NULL, "/", "abs unchanged 1");
  rel2abs_ok("/", "../foo", "/", "abs unchanged 2");

  rel2abs_ok("../../bin", "/usr/local/bin", "/usr/bin", "up and down");

  rel2abs_file_ok("../local/bin/perl", "/usr/bin/perl",
                  "/usr/local/bin/perl", "from file 1");
}

static void test_004(void) {
  abs2rel_ok("/usr/local/share/dict", "/usr/local/share", "dict",
             "no up");
  abs2rel_ok("/usr/local/share/dict", "/usr/local/share/doc", "../dict",
             "up, down");

  abs2rel_ok("/usr/local/share/dict/foo", "/usr/local/share/doc/bar",
             "../../dict/foo", "up, up, down, down (abs)");

  abs2rel_ok("dict/foo", "doc/bar",
             "../../dict/foo", "up, up, down, down (rel)");

  abs2rel_ok("/private/tmp", "/", "private/tmp", "close to root");
  abs2rel_file_ok("/private/tmp", "/tmp", "private/tmp",
                  "close to root");

  abs2rel_file_ok("/usr/local/bin/perl", "/usr/bin/perl",
                  "../local/bin/perl", "from file 1");
}

static void test_005(void) {
  splice_ok("foo", "bar", "foo/bar", "no slash");
  splice_ok("foo/", "bar", "foo/bar", "slash");
}

static void test_006(void) {
  temp_ok("x", NULL, ".x.tmp", "simple");
  temp_ok("/y/z/x", NULL, "/y/z/.x.tmp", "simple w/ path");
  temp_ok("x.json", NULL, ".x.tmp.json", "extension");
  temp_ok("/y/z/x.json", NULL, "/y/z/.x.tmp.json", "extension w/ path");
  temp_ok("x.bak/foo", NULL, "x.bak/.foo.tmp", "dot in path");
  temp_ok("x", ".abc123", ".x.abc123", "simple");
  temp_ok("/y/z/x", ".abc123", "/y/z/.x.abc123", "simple w/ path");
  temp_ok("x.json", ".abc123", ".x.abc123.json", "extension");
  temp_ok("/y/z/x.json", ".abc123", "/y/z/.x.abc123.json", "extension w/ path");
  temp_ok("x.bak/foo", ".abc123", "x.bak/.foo.abc123", "dot in path");
}


int main(void) {
  test_001();
  test_002();
  test_003();
  test_004();
  test_005();
  test_006();
  done_testing();
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
