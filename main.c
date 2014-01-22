/* main.c */

#include <jd_pretty.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include "digest.h"
#include "filename.h"
#include "find.h"
#include "manifest.h"
#include "md5.h"
#include "utils.h"

#define MANIFEST "MANIFEST.json"

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

static int unchanged(jd_var *ra, jd_var *rb) {
  static const char *keys[] = { /*"dev", "ino", "uid", "gid",*/ "size", /*"mode",*/ "mtime" };
  for (unsigned i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
    if (jd_compare(jd_get_ks(ra, keys[i], 0), jd_get_ks(rb, keys[i], 0)))
      return 0;
  }
  return 1;
}

static jd_var *relname(jd_var *out, jd_var *path, const char *dir) {
  char *rel = fn_abs2rel(jd_bytes(path, NULL), dir);
  jd_set_string(out, rel);
  free(rel);
  return out;
}

static void get_hash(jd_var *rec, jd_var *prec) {
  if (prec && unchanged(prec, rec)) {
    jd_var *hash = jd_get_ks(prec, "hash", 0);
    if (hash) jd_assign(jd_get_ks(rec, "hash", 1), hash);
  }
}

static void get_hash_from_list(jd_var *rec, jd_var *precs) {
  if (precs)
    get_hash(rec, jd_get_idx(precs, 0));
}

static void scan(jd_var *list, jd_var *prev, const char *dir) {
  scope {
    jd_var *by_name = mf_by_key(jd_nhv(1), prev, "name");
    jd_var *by_ino = mf_by_key(jd_nhv(1), prev, "dev.ino");
    jd_var *queue = jd_nav(100);
    jd_set_string(jd_push(queue, 1), dir);
    while (jd_count(queue)) {
      scope {
        jd_var *dn = jd_nv();
        jd_pop(queue, 1, dn);
        jd_var *files = find_read_dir(jd_nv(), dn);
        size_t nf = jd_count(files);
        for (int i = 0; i < (int) nf; i++) {
          struct stat st;
          jd_var *name = jd_get_idx(files, i);
          jd_var *rname = relname(jd_nv(), name, dir);
          /* Skip MANIFEST.json itself */
          if (!strcmp(MANIFEST, jd_bytes(rname, NULL))) continue;
          const char *fn = jd_bytes(name, NULL);
          if (lstat(fn, &st))
            jd_throw("Can't stat %s: %m", fn);
          if (S_ISDIR(st.st_mode)) {
            jd_assign(jd_push(queue, 1), name);
          }
          else {
            jd_var *rec = mk_file_rec(jd_push(list, 1), &st);

            /* Already got one? */
            get_hash_from_list(rec, jd_get_key(by_name, rname, 0));

            if (!jd_get_ks(rec, "hash", 0)) {
              jd_var *dev = jd_get_key(by_ino, jd_get_ks(rec, "dev", 0), 0);
              if (dev)
                get_hash_from_list(rec, jd_get_key(dev, jd_get_ks(rec, "ino", 0), 0));
            }

            if (!jd_get_ks(rec, "hash", 0)) {
              char digest[33];
              if (digest_file(fn, digest))
                jd_throw("Error computing MD5: %m");
              jd_set_string(jd_get_ks(rec, "hash", 1), digest);
              jd_printf("%s %s\n", digest, fn);
            }

            jd_assign(jd_get_ks(rec, "name", 1), rname);
            mf_add_by_key(by_ino, rec, "dev.ino");
          }
        }
      }
    }
  }
}

int main(int argc, char *argv[]) {
  jd_require("0.05");
  for (int i = 1; i < argc; i++) {
    scope {
      const char *dir = argv[i];
      char *mf = fn_splice(dir, MANIFEST);
      jd_var *list = jd_nav(1);
      jd_var *prev = jd_nhv(1);
      struct stat st;

      if (!stat(mf, &st)) {
        mf_load_file(prev, mf);
      }

      scan(list, prev, argv[i]);
      mf_save_file(list, mf);
      free(mf);
    }
  }
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
