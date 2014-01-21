/* main.c */

#include <stdio.h>

#include "digest.h"
#include "md5.h"
#include "utils.h"

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
