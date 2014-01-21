/* digest.h */

#ifndef DIGEST_H_
#define DIGEST_H_

#ifdef __cplusplus
extern "C" {
#endif

int digest_stream(FILE *stream, void *digest);
int digest_file(const char *filename, char *digest);

#ifdef __cplusplus
}
#endif

#endif

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
