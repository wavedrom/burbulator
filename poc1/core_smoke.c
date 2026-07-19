/* core_smoke: prove C23 _BitInt internal state + per-instance context.
   Compiled as C with gcc -std=c23 (NOT via Verilator's g++ - g++ lacks
   _BitInt). Linked as an object into every sim. DPI entry points live
   here directly (C linkage, chandle == void*). */
#include <stdlib.h>

#ifdef __cplusplus
extern "C" {          /* clang++ path (Verilator): keep DPI symbols C-linkage */
#endif

typedef struct {
    _BitInt(96) acc;      /* wide internal accumulator */
    unsigned long long step;
} ctr_ctx;

/* DPI: chandle ctr_new(int seed) */
void *ctr_new(int seed) {
    ctr_ctx *c = (ctr_ctx *)calloc(1, sizeof *c);
    c->acc  = seed;
    c->step = (unsigned)seed + 1u;
    return c;
}

/* DPI: longint ctr_next(chandle h) */
long long ctr_next(void *h) {
    ctr_ctx *c = (ctr_ctx *)h;
    c->acc += c->step;               /* _BitInt(96) arithmetic */
    return (long long)(unsigned long long)c->acc;  /* cast to DPI longint */
}

/* DPI: void ctr_free(chandle h) */
void ctr_free(void *h) { free(h); }

#ifdef __cplusplus
}
#endif
