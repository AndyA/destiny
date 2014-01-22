/* find.c */

#include <dirent.h>
#include <jd_pretty.h>
#include <stdio.h>
#include <stdlib.h>

#include "filename.h"
#include "find.h"

static char *tidy_splice(const char *path, const char *basename) {
  char *name = fn_splice(path, basename);
  char *tn = fn_tidy(name);
  free(name);
  return tn;
}

jd_var *find_read_dir(jd_var *out, jd_var *dir) {
  jd_set_array(out, 100);
  const char *dn = jd_bytes(dir, NULL);
  DIR *dirp = opendir(dn);
  if (dirp == NULL)
    return NULL;
  for (;;) {
    struct dirent *dp = readdir(dirp);
    if (!dp) break;
    if (dp->d_name[0] == '.') continue;
    char *fn = tidy_splice(dn, dp->d_name);
    jd_set_string(jd_push(out, 1), fn);
    free(fn);
  }
  closedir(dirp);
  return out;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
