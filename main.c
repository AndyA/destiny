/* main.c */

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <fcntl.h>
#include <unistd.h>

#include "destiny.h"
#include "md5.h"
#include "utils.h"

#define BLOCKSIZE 32768

static int digest_stream(FILE *stream, void *digest) {
  md5_ctx ctx;
  size_t sz;

  uint8_t *buffer = malloc(BLOCKSIZE + 72);
  if (!buffer)
    return 1;

  md5_init(&ctx);

  while (1) {
    size_t n;
    sz = 0;

    while (1) {
      n = fread(buffer + sz, 1, BLOCKSIZE - sz, stream);
      sz += n;

      if (sz == BLOCKSIZE)
        break;

      if (n == 0) {
        if (ferror(stream)) {
          free(buffer);
          return 1;
        }
        goto done;
      }

      if (feof(stream))
        goto done;
    }

    md5_loop(&ctx, buffer, BLOCKSIZE);
  }

done:

  /* Process any remaining bytes.  */
  if (sz > 0)
    md5_loop(&ctx, buffer, sz);

  md5_pad(&ctx);
  md5_hex(digest, &ctx);
  free(buffer);
  return 0;
}

static int digest_file(const char *filename, char *digest) {
  FILE *fp;
  int err;

  fp = fopen(filename, "rb");
  if (fp == NULL) return 1;
  posix_fadvise(fileno(fp), 0, 0, POSIX_FADV_SEQUENTIAL);
  err = digest_stream(fp, digest);
  fclose(fp);
  return err;
}

int main(int argc, char *argv[]) {
  for (int i = 1; i < argc; i++) {
    char digest[33];
    if (digest_file(argv[i], digest))
      die("Digest failed: %m");
    printf("%s %s\n", digest, argv[i]);
  }
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
