/* main.c */

#include <errno.h>
#include <getopt.h>
#include <jd_pretty.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#include "digest.h"
#include "filename.h"
#include "find.h"
#include "log.h"
#include "manifest.h"
#include "md5.h"
#include "utils.h"

#define PROG "destiny"
#define MANIFEST "MANIFEST.json"

#define MODE_BITS (S_IFMT | S_ISUID | S_ISGID | S_ISVTX | S_IRUSR | S_IWUSR | S_IXUSR)

static void usage() {
  fprintf(stderr, "Usage: " PROG " [options] <dir>...\n\n"
          "Options:\n"
          "  -h, --help                See this message\n"
          "  -q, --quiet               Be quiet\n"
          "      --set meta=value      Set additional meta field\n"
          "\n" PROG " %s\n", v_info);
  exit(1);
}

static void parse_set(jd_var *ctx, const char *arg) {
  char *sp = strchr(arg, '=');
  if (!sp) jd_throw("Expected --set name=var");
  scope {
    jd_assign(jd_get_key(ctx, jd_set_bytes(jd_nv(), arg, sp - arg), 1), jd_nsv(sp + 1));
  }
}

static void parse_options(jd_var *ctx, int *argc, char ***argv) {
  int ch, oidx;

  static struct option opts[] = {
    {"help", no_argument, NULL, 'h'},
    {"quiet", no_argument, NULL, 'q'},
    {"set", required_argument, NULL, 1},
    {NULL, 0, NULL, 0}
  };

  while (ch = getopt_long(*argc, *argv, "qh", opts, &oidx), ch != -1) {
    switch (ch) {
    case 1:
      parse_set(ctx, optarg);
      break;
    case 'h':
    default:
      usage();
      break;
    case 'q':
      log_level = WARNING;
      break;
    }
  }

  *argc -= optind;
  *argv += optind;

  if (*argc == 0) {
    usage();
  }
}

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

static jd_var *get_link(jd_var *out, const char *path, size_t bufsize) {
  char buf[bufsize];
  ssize_t len;
  if (len = readlink(path, buf, bufsize), len == -1) {
    if (errno == ENAMETOOLONG)
      return get_link(out, path, bufsize * 2);
    jd_throw("Can't read link %s: %s", path, strerror(errno));
  }
  return jd_set_bytes(out, buf, len);
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
        jd_var *subs = jd_nav(10);
        jd_pop(queue, 1, dn);
        log_info("Scanning %V", dn);
        jd_var *files = jd_nav(0);
        if (!find_read_dir(files, dn))
          log_error("Can't read %s: %s", dn, strerror(errno));
        jd_sort(files);
        size_t nf = jd_count(files);
        for (int i = 0; i < (int) nf; i++) {
          struct stat st;
          jd_var *name = jd_get_idx(files, i);
          jd_var *rname = relname(jd_nv(), name, dir);
          /* Skip MANIFEST.json itself */
          if (!strcmp(MANIFEST, jd_bytes(rname, NULL))) continue;
          const char *fn = jd_bytes(name, NULL);
          if (lstat(fn, &st)) {
            log_error("Can't stat %s: %s", strerror(errno));
            continue;
          }

          /*
          S_ISREG(m)  is it a regular file?
          S_ISDIR(m)  directory?
          S_ISCHR(m)  character device?
          S_ISBLK(m)  block device?
          S_ISFIFO(m) FIFO (named pipe)?
          S_ISLNK(m)  symbolic link?  (Not in POSIX.1-1996.)
          S_ISSOCK(m) socket?  (Not in POSIX.1-1996.)
          */

          if (S_ISDIR(st.st_mode)) {
            jd_assign(jd_unshift(subs, 1), name);
          }
          else {
            jd_var *rec = mk_file_rec(jd_push(list, 1), &st);

            if (S_ISREG(st.st_mode)) {
              /* Already got one? */
              get_hash_from_list(rec, jd_get_key(by_name, rname, 0));

              if (!jd_get_ks(rec, "hash", 0)) {
                jd_var *dev = jd_get_key(by_ino, jd_get_ks(rec, "dev", 0), 0);
                if (dev)
                  get_hash_from_list(rec, jd_get_key(dev, jd_get_ks(rec, "ino", 0), 0));
              }

              if (!jd_get_ks(rec, "hash", 0)) {
                char digest[33];
                if (digest_file(fn, digest)) {
                  log_error("Error computing MD5 for %V: %s", name, strerror(errno));
                }
                else {
                  jd_set_string(jd_get_ks(rec, "hash", 1), digest);
                  log_info("%s %s\n", digest, fn);
                }
              }
            }
            else if (S_ISLNK(st.st_mode)) {
              get_link(jd_get_ks(rec, "link", 1), fn, 1024);
            }
            else if (S_ISCHR(st.st_mode) || S_ISBLK(st.st_mode)) {
              jd_sprintf(jd_get_ks(rec, "rdev", 1), "0x%llx",
                         (unsigned long long) st.st_rdev);
            }

            jd_assign(jd_get_ks(rec, "name", 1), rname);
            mf_add_by_key(by_ino, rec, "dev.ino");
          }
        }
        jd_append(queue, subs);
      }
    }
  }
}

static jd_var *new_manifest(jd_var *out) {
  jd_set_hash(out, 2);
  jd_set_hash(jd_get_ks(out, "meta", 1), 10);
  jd_set_array(jd_get_ks(out, "object", 1), 1);
  return out;
}

static void set_meta(jd_var *manifest, jd_var *def, const char *root, const char *mf) {
  char hostname[256];
  jd_var *meta = jd_get_ks(manifest, "meta", 1);
  if (meta->type != HASH) jd_set_hash(meta, 10);
  if (def) jd_merge(meta, def, 0);
  jd_set_string(jd_get_ks(meta, "root", 1), root);
  jd_set_string(jd_get_ks(meta, "manifest", 1), mf);
  if (gethostname(hostname, sizeof(hostname)))
    jd_throw("Can't get hostname: %s", strerror(errno));
  jd_set_string(jd_get_ks(meta, "host", 1), hostname);
  jd_set_int(jd_get_ks(meta, "time", 1), (jd_int) time(NULL));
}

int main(int argc, char *argv[]) {
  jd_require("0.05");
  scope {
    jd_var *ctx = jd_nhv(10);
    parse_options(ctx, &argc, &argv);
    log_info("%s %s", PROG, v_info);
    for (int i = 0; i < argc; i++) {
      scope {
        char *dir = fn_rel2abs(argv[i], NULL);
        char *bn = fn_basename(dir);
        if (!strcmp(bn, MANIFEST)) {
          char *t = fn_dirname(dir);
          free(dir);
          dir = t;
        }
        free(bn);

        char *mf = fn_splice(dir, MANIFEST);

        jd_var *manifest = new_manifest(jd_nv());
        jd_var *list = jd_get_ks(manifest, "object", 0);
        jd_var *prev = jd_nav(1);
        jd_var *lctx = ctx;

        struct stat st;
        if (!stat(mf, &st)) {
          log_info("Reading %s", mf);
          jd_var *prevm = mf_upgrade(jd_nv(), mf_load_file(jd_nv(), mf));
          prev = jd_get_ks(prevm, "object", 0);
          lctx = jd_clone(jd_nv(), ctx, 0);
          jd_merge(lctx, jd_get_ks(prevm, "meta", 0), 0);
        }

        set_meta(manifest, lctx, dir, mf);
        scan(list, prev, dir);

        log_info("Writing %s", mf);
        mf_save_file_atomic(manifest, mf);
        free(dir);
        free(mf);
      }
    }
  }
  return 0;
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */















