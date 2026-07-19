/* burbulator PoC - source/sink logic in C.
   C23 _BitInt internal datapath/checksum; cast to DPI types at boundary.
   Per-instance context (chandle) -> multiple instances independent. */
#include <stdlib.h>
#include "burb.h"

#define CHK_P 0x100000001b3ULL      /* FNV-64 prime, folded into 128-bit acc */

/* xorshift64* PRNG - reproducible across compilers, not libc rand(). */
static unsigned long long xs64(unsigned long long *s) {
    unsigned long long x = *s;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    *s = x;
    return x * 0x2545F4914F6CDD1DULL;
}

/* ---------------- source ---------------- */
typedef struct {
    unsigned long long d_st, b_st;  /* data + bubble PRNG states (independent) */
    unsigned _BitInt(128) chk;
    unsigned _BitInt(DW)  cur;      /* current beat, DW-wide (unsigned: zero-extend like HW) */
    int bubble_pct, ntxn, have;
    int cnt;                        /* beats produced (<= ntxn) */
} src_ctx;

void *src_new(int seed, int bubble_pct, int dw, int ntxn) {
    (void)dw;                       /* width is compile-time via _BitInt(DW) */
    src_ctx *c = (src_ctx *)calloc(1, sizeof *c);
    c->d_st = (unsigned)seed | 1ULL;            /* nonzero */
    c->b_st = ((unsigned)seed ^ 0xBu) | 1ULL;   /* independent stream */
    c->bubble_pct = bubble_pct;
    c->ntxn = ntxn;
    return c;
}

void src_tick(void *h, svBit accepted, svBit *valid, long long *data) {
    src_ctx *c = (src_ctx *)h;
    if (accepted) c->have = 0;      /* held beat was taken */
    if (!c->have && c->cnt < c->ntxn) {
        if (xs64(&c->b_st) % 100 >= (unsigned)c->bubble_pct) {   /* not a bubble */
            c->cur = (unsigned _BitInt(DW))xs64(&c->d_st);
            c->chk = c->chk * CHK_P + (unsigned long long)c->cur;
            c->cnt++;
            c->have = 1;
        }
    }
    *valid = (svBit)c->have;
    *data  = (long long)(unsigned long long)c->cur;   /* held stable until taken */
}

long long src_checksum(void *h) { return (long long)(unsigned long long)((src_ctx *)h)->chk; }
int       src_count(void *h)    { return ((src_ctx *)h)->cnt; }
void      src_free(void *h)     { free(h); }

/* ---------------- sink ---------------- */
typedef struct {
    unsigned long long p_st;        /* backpressure PRNG state */
    unsigned _BitInt(128) chk;
    int backp_pct, last_ready, cnt;
} snk_ctx;

void *snk_new(int seed, int backp_pct) {
    snk_ctx *c = (snk_ctx *)calloc(1, sizeof *c);
    c->p_st = ((unsigned)seed ^ 0xCu) | 1ULL;   /* independent stream */
    c->backp_pct = backp_pct;
    c->last_ready = 0;              /* matches i_0_ack reset = 0 */
    return c;
}

void snk_tick(void *h, svBit valid, long long data, svBit *ready_next) {
    snk_ctx *c = (snk_ctx *)h;
    if (valid && c->last_ready) {   /* transfer this cycle */
        c->chk = c->chk * CHK_P + (unsigned long long)data;
        c->cnt++;
    }
    c->last_ready = (xs64(&c->p_st) % 100 >= (unsigned)c->backp_pct) ? 1 : 0;
    *ready_next = (svBit)c->last_ready;
}

int       snk_done(void *h, int ntxn) { return ((snk_ctx *)h)->cnt >= ntxn; }
long long snk_checksum(void *h)        { return (long long)(unsigned long long)((snk_ctx *)h)->chk; }
int       snk_count(void *h)           { return ((snk_ctx *)h)->cnt; }
void      snk_free(void *h)            { free(h); }

/* ---------------- reference model (poc2) ----------------
   Expected checksum of op(a[n], b[n]) for n in [0,ntxn), where a/b are the
   data streams from src_new(seedA)/src_new(seedB) (timing-independent).
   op: 0 = a+b, 1 = a-b. DW-wide wrap matches the HW adder/subtractor. */
long long combine_ref(int seedA, int seedB, int ntxn, int op) {
    unsigned long long as = (unsigned)seedA | 1ULL;
    unsigned long long bs = (unsigned)seedB | 1ULL;
    unsigned _BitInt(128) chk = 0;
    for (int n = 0; n < ntxn; n++) {
        unsigned _BitInt(DW) a = (unsigned _BitInt(DW))xs64(&as);
        unsigned _BitInt(DW) b = (unsigned _BitInt(DW))xs64(&bs);
        unsigned _BitInt(DW) r = op ? (unsigned _BitInt(DW))(a - b)
                                    : (unsigned _BitInt(DW))(a + b);
        chk = chk * CHK_P + (unsigned long long)r;
    }
    return (long long)(unsigned long long)chk;
}
