/* basic.t */

#include "tap.h"

static struct {
  const char *md5;
  const char *data;
} test_data[] = {
#include "md5.data"
  { NULL, NULL }
};

static void test_md5(void) {
  for (int i = 0; test_data[i].md5; i++) {
    diag("md5=%s, data=%s", test_data[i].md5, test_data[i].data);
  }
  pass("It's OK");
}

int main(void) {
  test_md5();
  done_testing();
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */



