/* multicoder.h */

#ifndef __MULTICODER_H
#define __MULTICODER_H

#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

#include "jd_pretty.h"

#define LOG_LEVELS \
  X(FATAL)    \
  X(ERROR)    \
  X(WARNING)  \
  X(INFO)     \
  X(DEBUG)

/* Error levels */
#define X(x) x,
enum {
  LOG_LEVELS
  MAXLEVEL
};
#undef X

extern unsigned log_level;
extern unsigned log_colour;

unsigned log_decode_level(const char *name);
void log_set_thread(const char *name);
const char *log_get_thread(void);

void log_debug(const char *msg, ...);
void log_info(const char *msg, ...);
void log_warning(const char *msg, ...);
void log_error(const char *msg, ...);
void log_fatal(const char *msg, ...);

#endif

/* vim:ts=2:sw=2:sts=2:et:ft=c
 */
