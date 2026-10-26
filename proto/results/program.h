#ifndef FILTER_PROGRAM_H
#define FILTER_PROGRAM_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
/* Single host thread; Julia ccallable entrypoints auto-initialize the runtime.
 * The caller supplies valid writable out pointers (null is checked).
 * Outputs remain unchanged on failure; exceptions may mutate state.
 * Handle: generation << 32 | slot; 0 is invalid. No generation reuse. */
enum { filter_OK=0, filter_INVALID=1, filter_EXHAUSTED=2,
       filter_NULL=3, filter_EXCEPTION=4 };
int32_t filter_create(uint64_t *out);
int32_t filter_destroy(uint64_t h);
int32_t filter_step(uint64_t h, double a1, double *out);
int32_t filter_value(uint64_t h, double *out);
int32_t filter_checked(uint64_t h, int32_t a1, int32_t *out);
int32_t filter_clear(uint64_t h);
#ifdef __cplusplus
}
#endif
#endif
