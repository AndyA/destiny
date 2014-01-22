/* log.c */

#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "log.h"
#include "utils.h"

#define TS_FORMAT "%Y/%m/%d %H:%M:%S"

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_key_t tn_key;
static unsigned max_name = 0;

unsigned log_level  = DEBUG;
int log_colour = -1;

#define X(x) #x,
static const char *lvl[] = {
  LOG_LEVELS
  NULL
};
#undef X

static const char *lvl_col[] = {
  "\x1b[41m" "\x1b[37m",  // ERROR    white on red
  "\x1b[41m" "\x1b[37m",  // FATAL    white on red
  "\x1b[31m",             // WARNING  red
  "\x1b[36m",             // INFO     cyan
  "\x1b[32m",             // DEBUG    green
};

#define COLOUR_RESET "\x1b[0m"

static void ts(char *buf, size_t sz) {
  struct timeval tv;
  struct tm *tmp;
  size_t len;
  gettimeofday(&tv, NULL);
  tmp = gmtime(&tv.tv_sec);
  if (!tmp) jd_throw("gmtime failed: %s", strerror(errno));
  len = strftime(buf, sz, TS_FORMAT, tmp);
  snprintf(buf + len, sz - len, ".%06lu", (unsigned long) tv.tv_usec);
}

static pthread_key_t thread_key() {
  static int done_init = 0;
  if (!done_init) {
    pthread_key_create(&tn_key, free);
    done_init++;
  }
  return tn_key;
}

void log_set_thread(const char *name) {
  pthread_key_t key = thread_key();
  char *old = pthread_getspecific(key);
  if (old) free(old);
  pthread_setspecific(key, sstrdup(name));
}

const char *log_get_thread(void) {
  return pthread_getspecific(thread_key());
}

unsigned log_decode_level(const char *name) {
  for (unsigned i = 0; i < MAXLEVEL; i++)
    if (!strcmp(name, lvl[i])) return i;
  jd_throw("Bad log level: %s", name);
}

static void log(unsigned level, const char *msg, va_list ap) {
  if (level <= log_level) scope {
    if (log_colour == -1)
      log_colour = !!isatty(fileno(stdout));
    const char *col_on = log_colour ? lvl_col[level] : "";
    const char *col_off = log_colour ? COLOUR_RESET : "";
    char tmp[30];
    unsigned i;
    size_t count;
    jd_var *ldr = jd_nv(), *str = jd_nv(), *ln = jd_nv();
    const char *pname = log_get_thread();
    if (!pname && max_name) pname = "anon";

    ts(tmp, sizeof(tmp));

    pthread_mutex_lock(&mutex);
    if (pname) {
      size_t len = strlen(pname);
      if (len > max_name) max_name = len;
      jd_var *fmt = jd_sprintf(jd_nv(), "%%s | %%5lu | %%-%ds | %%-7s | ", max_name);
      jd_sprintvf(ldr, fmt, tmp, (unsigned long) getpid(),
      log_get_thread(), lvl[level]);
    }
    else {
      jd_sprintf(ldr, "%s | %5lu | %-7s | ", tmp, (unsigned long) getpid(), lvl[level]);

    }
    jd_vsprintf(str, msg, ap);
    jd_split(ln, str, jd_nsv("\n"));
    count = jd_count(ln);
    jd_var *last = jd_get_idx(ln, count - 1);
    if (jd_length(last) == 0) count--;

    for (i = 0; i < count; i++) {
      jd_fprintf(stderr, "%s%V%V%s\n", col_on, ldr, jd_get_idx(ln, i), col_off);
    }
    pthread_mutex_unlock(&mutex);
  }
}

#define LOGGER(name, level)          \
  void name(const char *msg, ...) {  \
    va_list ap;                      \
    va_start(ap, msg);               \
    log(level, msg, ap);          \
    va_end(ap);                      \
  }

LOGGER(log_debug,    DEBUG)
LOGGER(log_info,     INFO)
LOGGER(log_warning,  WARNING)
LOGGER(log_error,    ERROR)
LOGGER(log_fatal,    FATAL)

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
