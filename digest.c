/* digest.c */

#include <stdio.h>
#include <stdlib.h>

#include "digest.h"
#include "md5.h"
#include "utils.h"

#define BLOCKSIZE 32768

int digest_stream(FILE *stream, void *digest) {
  md5_ctx ctx;
  size_t sz;

  uint8_t *buffer = alloc(BLOCKSIZE + 72);

  md5_init(&ctx);

  for (;;) {
    size_t n;
    sz = 0;

    for (;;) {
      n = fread(buffer + sz, 1, BLOCKSIZE - sz, stream);
      sz += n;

      if (sz == BLOCKSIZE)
        break;

      if (n == 0) {
        if (ferror(stream)) goto fail;
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

fail:
  free(buffer);
  return 1;
}

int digest_file(const char *filename, char *digest) {
  FILE *fp;
  int err;

  fp = fopen(filename, "rb");
  if (fp == NULL) return 1;
  /*  posix_fadvise(fileno(fp), 0, 0, POSIX_FADV_SEQUENTIAL);*/
  err = digest_stream(fp, digest);
  fclose(fp);
  return err;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
