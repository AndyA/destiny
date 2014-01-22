/* manifest.c */

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "manifest.h"

static jd_var *mk_array(jd_var *hash, jd_var *key) {
  if (hash->type != HASH) jd_set_hash(hash, 1);
  jd_var *ar = jd_get_key(hash, key, 1);
  if (ar->type != ARRAY) jd_set_array(ar, 1);
  return ar;
}

static jd_var *mk_slot(jd_var *hash, jd_var *key) {
  return jd_push(mk_array(hash, key), 1);
}

static void add_by_key(jd_var *out, jd_var *rec, jd_var *keys, int pos) {
  jd_var *key = jd_get_key(rec, jd_get_idx(keys, pos), 0);
  if (!key) return;
  if (pos != (int) jd_count(keys) - 1) {
    if (out->type != HASH) jd_set_hash(out, 1);
    add_by_key(jd_get_key(out, key, 1), rec, keys, pos + 1);
  }
  else
    jd_assign(mk_slot(out, key), rec);
}

jd_var *mf_add_by_keys(jd_var *out, jd_var *rec, jd_var *keys) {
  add_by_key(out, rec, keys, 0);
  return out;
}

jd_var *mf_add_by_key(jd_var *out, jd_var *rec, const char *key) {
  scope {
    mf_add_by_keys(out, rec, jd_split(jd_nav(10), jd_nsv(key), jd_nsv(".")));
  }
  return out;
}

jd_var *mf_by_keys(jd_var *out, jd_var *list, jd_var *keys) {
  size_t count = jd_count(list);
  for (int i = 0; i < (int) count; i++) {
    mf_add_by_keys(out, jd_get_idx(list, i), keys);
  }
  return out;
}

jd_var *mf_by_key(jd_var *out, jd_var *list, const char *key) {
  scope {
    mf_by_keys(out, list, jd_split(jd_nav(10), jd_nsv(key), jd_nsv(".")));
  }
  return out;
}

jd_var *mf_load_string(jd_var *out, FILE *f) {
  char buf[0x10000];
  size_t got;

  jd_set_empty_string(out, 1);
  while (got = fread(buf, 1, sizeof(buf), f), got)
    jd_append_bytes(out, buf, got);
  return out;
}

jd_var *mf_load_json(jd_var *out, FILE *f) {
  jd_var json = JD_INIT;
  jd_from_json(out, mf_load_string(&json, f));
  jd_release(&json);
  return out;
}

jd_var *mf_load_file(jd_var *out, const char *fn) {
  FILE *fl = fopen(fn, "r");
  if (!fl) jd_throw("Can't read %s: %m\n", fn);
  jd_var *v = mf_load_json(out, fl);
  fclose(fl);
  return v;
}

void mf_save_file(jd_var *out, const char *fn) {
  size_t sz;
  FILE *fl = fopen(fn, "w");
  if (!fl) jd_throw("Can't write %s: %m", fn);
  jd_var json = JD_INIT;
  jd_to_json(&json, out);
  const char *js = jd_bytes(&json, &sz);
  size_t done = fwrite(js, 1, sz, fl);
  if (done != sz) jd_throw("Error writing %s: %m", fn);
  jd_release(&json);
  fclose(fl);
}

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */


