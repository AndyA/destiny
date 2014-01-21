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

static void to_hex(char *out, const uint8_t *digest) {
  sprintf(out,
          "%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
          digest[0], digest[1], digest[2], digest[3],
          digest[4], digest[5], digest[6], digest[7],
          digest[8], digest[9], digest[10], digest[11],
          digest[12], digest[13], digest[14], digest[15]);
}

static void md5(char *out, const char *in, size_t len) {
  uint8_t digest[16];
  md5_ctxt ctx;

  md5_init(&ctx);
  md5_loop(&ctx, (uint8_t *) in, (unsigned) len);
  md5_pad(&ctx);
  md5_result(digest, &ctx);
  to_hex(out, digest);
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








