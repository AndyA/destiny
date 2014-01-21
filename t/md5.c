/* basic.t */

#include <stdint.h>
#include <string.h>

#include "tap.h"
#include "md5.h"

static struct {
  const char *md5;
  const char *data;
} test_data[] = {
#include "md5.data"
  { NULL, NULL }
};

static void md5(char *out, const char *in, size_t len) {
  md5_ctxt ctx;

  md5_init(&ctx);
  md5_loop(&ctx, (uint8_t *) in, len);
  md5_pad(&ctx);
  md5_hex(out, &ctx);
}

static void test_md5(void) {
  for (int i = 0; test_data[i].md5; i++) {
    char out[33];
    md5(out, test_data[i].data, strlen(test_data[i].data));
    if (!ok(!strcmp(out, test_data[i].md5),
            "\"%s\": got %s", test_data[i].data, test_data[i].md5)) {
      diag("wanted=%s, got=%s", test_data[i].md5, out);
    }
  }
}

int main(void) {
  test_md5();
  done_testing();
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */










