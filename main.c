/* main.c */

#include <jd_pretty.h>
#include <stdio.h>
#include <sys/stat.h>

#include "digest.h"
#include "find.h"
#include "md5.h"
#include "utils.h"

#define MODE_BITS (S_IFMT | S_ISUID | S_ISGID | S_ISVTX | S_IRUSR | S_IWUSR | S_IXUSR)

static jd_var *mk_file_rec(jd_var *out, const struct stat *st) {
  jd_set_hash(out, 10);
  jd_sprintf(jd_get_ks(out, "dev", 1), "0x%llx", (unsigned long long) st->st_dev);
  jd_sprintf(jd_get_ks(out, "ino", 1), "0x%llx", (unsigned long long) st->st_ino);
  jd_sprintf(jd_get_ks(out, "uid", 1), "%llu", (unsigned long long) st->st_uid);
  jd_sprintf(jd_get_ks(out, "gid", 1), "%llu", (unsigned long long) st->st_gid);
  jd_sprintf(jd_get_ks(out, "size", 1), "%llu", (unsigned long long) st->st_size);
  jd_sprintf(jd_get_ks(out, "mode", 1), "0%llo",
             (unsigned long long) st->st_mode & MODE_BITS);
  jd_sprintf(jd_get_ks(out, "mtime", 1), "%llu", (unsigned long long) st->st_mtime);

  return out;
}

static void scan(jd_var *list, const char *dir) {
  scope {
    jd_var *queue = jd_nav(100);
    jd_set_string(jd_push(queue, 1), dir);
    while (jd_count(queue)) {
      jd_var *dn = jd_nv();
      jd_pop(queue, 1, dn);
      jd_var *files = find_read_dir(jd_nv(), dn);
      size_t nf = jd_count(files);
      for (int i = 0; i < (int) nf; i++) {
        struct stat st;
        const char *fn = jd_bytes(jd_get_idx(files, i), NULL);
        if (lstat(fn, &st))
          jd_throw("Can't stat %s: %m", fn);
        if (S_ISDIR(st.st_mode)) {
          jd_assign(jd_push(queue, 1), jd_get_idx(files, i));
        }
        else {
          jd_var *rec = mk_file_rec(jd_push(list, 1), &st);
          jd_assign(jd_get_ks(rec, "name", 1), jd_get_idx(files, i));
        }
      }
    }
  }
}

int main(int argc, char *argv[]) {
  scope {
    jd_var *list = jd_nav(1);
    for (int i = 1; i < argc; i++) {
      scan(list, argv[i]);
    }
    jd_printf("%lJ", list);
  }
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
