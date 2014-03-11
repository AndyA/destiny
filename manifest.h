/* manifest.h */

#ifndef MANIFEST_H_
#define MANIFEST_H_

#ifdef __cplusplus
extern "C" {
#endif

#include <jd_pretty.h>

jd_var *mf_add_by_keys(jd_var *out, jd_var *rec, jd_var *keys);
jd_var *mf_add_by_key(jd_var *out, jd_var *rec, const char *key);
jd_var *mf_by_keys(jd_var *out, jd_var *list, jd_var *keys);
jd_var *mf_by_key(jd_var *out, jd_var *list, const char *key);

jd_var *mf_load_string(jd_var *out, FILE *f);
jd_var *mf_load_json(jd_var *out, FILE *f);
jd_var *mf_load_file(jd_var *out, const char *fn);
void mf_save_file(jd_var *out, const char *fn);
void mf_save_file_atomic(jd_var *out, const char *fn);
jd_var *mf_upgrade(jd_var *out, jd_var *in);

#ifdef __cplusplus
}
#endif

#endif

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
