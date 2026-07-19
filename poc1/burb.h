/* burbulator PoC - DPI-C source/sink shared decls.
   Compiles as C (Questa) and C++ (Verilator/clang++). */
#ifndef BURB_H
#define BURB_H

#include <svdpi.h>

#ifndef DW
#define DW 64            /* data width; mirror of SV -GDW / -gDW */
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* A - source: PRNG data + random bubbles, order-sensitive checksum */
void*     src_new(int seed, int bubble_pct, int dw, int ntxn);
void      src_tick(void *h, svBit accepted, svBit *valid, long long *data);
long long src_checksum(void *h);
int       src_count(void *h);
void      src_free(void *h);

/* C - sink: checksum scoreboard + random backpressure */
void*     snk_new(int seed, int backp_pct);
void      snk_tick(void *h, svBit valid, long long data, svBit *ready_next);
int       snk_done(void *h, int ntxn);
long long snk_checksum(void *h);
int       snk_count(void *h);
void      snk_free(void *h);

/* reference model: expected checksum of op(a,b) over ntxn beats.
   op 0=a+b, 1=a-b. Used by poc2 (radix2 = {a+b, a-b}). */
long long combine_ref(int seedA, int seedB, int ntxn, int op);

#ifdef __cplusplus
}
#endif

#endif
