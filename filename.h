/* filename.h */

#ifndef __FILENAME_H
#define __FILENAME_H

int fn_is_url(const char *fn);
int fn_is_abs(const char *fn);
char *fn_tidy(const char *name);
char *fn_basename(const char *file);
char *fn_dirname(const char *file);
char *fn_rel2abs(const char *rel, const char *base);
char *fn_rel2abs_file(const char *rel, const char *base_file);
char *fn_abs2rel(const char *abs, const char *base);
char *fn_abs2rel_file(const char *abs, const char *base_file);
char *fn_splice(const char *path, const char *basename);
char *fn_temp(const char *name, const char *cookie);

#endif

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
