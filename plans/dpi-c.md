# PoC: valid/ready/data stream with DPI-C bubbles

Simple data/valid/ready interface. Verilog project.
Prove bubble (source-side idle) + backpressure (sink-side stall) handling
across a registered handshake, with source/sink logic in C via DPI-C.

## Supported simulators
* Verilator   ← PoC target — DPI-C, **built with clang++** (see toolchain)
* QuestaSim   ← PoC target — DPI-C (Lattice OEM 2024.2), `-ccflags -std=c23`
* VCS         (later) — DPI-C
* ~~Icarus Verilog~~ **DROPPED** — no DPI-C support (VPI only). Out of scope.

**Milestone 1 (smoke tests) DONE** — `poc1/smoke2_tb.sv` + `core_smoke.c`
+ `Makefile` (`make vl|qs`). Both print `SMOKE2 PASS`. Proved: DPI-C,
`chandle` per-instance context, C23 `_BitInt` internal, multi-instance.

## Toolchain (locked by milestone 1)

- **DPI-C only.** Icarus 13 has no DPI (`import "DPI-C"` = syntax error);
  dropped. All backends use standard DPI-C — one `core.c`, no VPI shim.
- **C23 `_BitInt(N)`** for internal datapath/checksum arithmetic; cast to
  DPI types (`longint`/`svBitVecVal`) only at the SV boundary.
- **g++ does NOT support `_BitInt`; clang++ does.** Verilator compiles user
  `.c` as C++ → must build with clang++ (`--compiler clang -MAKEFLAGS
  "CXX=clang++ LINK=clang++" -CFLAGS -std=c++23`). Questa's `vlog` compiles
  the C as C → `-ccflags -std=c23`.
- **`core.c` must compile as both C and C++**: wrap in `extern "C"` guard
  (keeps DPI symbols C-linkage under clang++); cast all `void*` explicitly
  (`(ctx*)malloc/h`) — implicit `void*→T*` is a C++ error.
- **Per-instance context via `chandle`** (== C `void*`). `src_new()`/
  `snk_new()` return a chandle; every tick/query takes it. No statics →
  multiple source/sink instances independent. `chandle` is native on
  Verilator/Questa/VCS.
- **64-bit across DPI**: plain `longint` return/args work on these sims
  (the 32-bit-truncation problem was Icarus-VPI-only, now moot).
- **Verilator gotcha**: a comment whose first word is `verilator` (any case)
  is parsed as a pragma → `BADVLTPRAGMA`. Don't start comments with it.

## Blocks

DUT built in `poc1/top.v`. Signal naming: **req = valid, ack = ready**.
`t_0` = upstream/target port (source A connects), `i_0` = downstream/
initiator port (sink C connects).

```
A ──t_0_req/t_0_dat──▶ B ──i_0_req/i_0_dat──▶ C
  ◀────t_0_ack────────   ◀────i_0_ack─────────
                    (D wraps clock/reset)
```

| id | role | language | drives | observes |
|----|------|----------|--------|----------|
| A  | source: PRNG data + random bubbles | DPI-C | t_0_req, t_0_dat | t_0_ack |
| B  | DUT: **3-stage elastic pipeline** (Carloni half-buffers), `top.v` | Verilog | t_0_ack, i_0_req, i_0_dat | t_0_req, t_0_dat, i_0_ack |
| C  | sink: checksum scoreboard + random backpressure | DPI-C | i_0_ack | i_0_req, i_0_dat |
| D  | testbench: clock, reset, wiring, DPI calls, $finish | SystemVerilog | clk, rst | done |

DUT: 3 data regs d1/d2/d3, per-stage control `en=req&ack`,
`req_next=req|~ack`, `ack=down_ack|~down_req`. `req` registered, `ack`
combinational up the chain (acyclic). 3-deep buffering, 3-cycle latency,
in-order, no drop/dup → checksum scoreboard valid. DW=64.

## Handshake contract

- Transfer on posedge when `req && ack` (valid && ready).
- DUT: `req` registered, `ack` combinational. Source drives registered
  `t_0_req`, samples comb `t_0_ack`. Sink drives **registered** `i_0_ack`,
  samples registered `i_0_req`. No comb loop (DPI outputs are latched in SV
  before feeding DUT).
- Data = **seeded pseudo-random** (PRNG in A, masked to DW). Verify by
  **checksum**: A accumulates order-sensitive checksum of sent beats, C of
  received beats. At end compare `src_checksum == snk_checksum` && counts.
  Catches drop/dup/corruption (pipeline is in-order).

## Knobs

Runtime plusargs (read in D via `$value$plusargs`, passed to DPI `*_new`):
| plusarg | meaning | default |
|---------|---------|---------|
| `+seed=`     | PRNG seed (data + bubble + backpressure streams derived) | 1 |
| `+ntxn=`     | transactions before $finish | 1000 |
| `+bubble=`   | source bubble probability % (0=full rate) | 20 |
| `+backp=`    | sink backpressure probability % (0=never stall) | 20 |

Compile-time knob (NOT a plusarg — sizes buses at elaboration):
- `DW` via Verilator `-GDW=<n>` / Questa `-gDW=<n>`. Default 64.
- Mirror to C as `-DDW=<n>` so `_BitInt(DW)` matches the bus width.
- PoC caps `DW<=64` (fits `longint` at the DPI boundary). DW>64 would need
  `svBitVecVal` array packing — out of scope.

PRNG streams must be independent: seed data-PRNG with `seed`, bubble-PRNG
with `seed^0xB`, backpressure-PRNG with `seed^0xC` — else bubble decisions
perturb the data sequence.

Use a self-contained PRNG (**xorshift64** in `core.c`), NOT libc `rand()`
— reproducible across machines/compilers. Since data stream is independent
of bubble/backpressure timing and checksum is order-sensitive over emission
order, **checksum is identical across all sims for the same seed** regardless
of stall patterns. That cross-sim match is the equivalence check.

## DPI-C model — C decides per clock, per instance

C holds all timing/randomness/checksum state in a per-instance context
(chandle). SV just latches results each posedge. Internals use `_BitInt`;
boundary uses `chandle`/`longint`/`bit`.

```c
// core.c internals (compiled C or C++; extern "C" on all DPI symbols)
typedef struct { _BitInt(DW) cur; _BitInt(128) chk; unsigned long long
                 d_st, b_st; int dw, bubble_pct, have; long cnt; } src_ctx;

// A — source
chandle  src_new(input int seed, input int bubble_pct, input int dw);
// accepted = (t_0_req && t_0_ack) sampled this cycle (current beat taken)
void     src_tick(chandle h, input bit accepted,
                  output bit valid, output longint data);
//   if (accepted) c->have = 0;
//   if (!c->have && bubble_rng(c)%100 >= c->bubble_pct) {
//       c->cur = xorshift64(&c->d_st);          // _BitInt(DW), masked
//       c->chk = c->chk*P + c->cur; c->have = 1; // order-sensitive checksum
//   }
//   *valid = c->have; *data = (longint)c->cur;   // held stable until accepted
longint  src_checksum(chandle h);   // (longint)(c->chk truncated)
int      src_count(chandle h);
void     src_free(chandle h);

// C — sink   (symmetric snk_ctx, snk_new/tick/checksum/count/free)
void     snk_tick(chandle h, input bit valid, input longint data,
                  output bit ready_next);
//   if (valid && c->last_ready) { c->chk = c->chk*P + data; c->cnt++; }
//   c->last_ready = (backp_rng(c)%100 >= c->backp_pct);
//   *ready_next = c->last_ready;
int      snk_done(chandle h, input int ntxn);   // cnt >= ntxn
```

Final check in D at `snk_done`: PASS iff `src_count==snk_count==ntxn`
&& `src_checksum()==snk_checksum()`; `$display` result, then `$finish`.

SV testbench D, each posedge (post-reset):
```
accepted = t_0_req & t_0_ack;                 // t_0_ack comb from DUT
if (src_count(sh) < ntxn)                      // stop offering after N sent
    src_tick(sh, accepted, sv, sd);
else sv = 0;                                    // source idle, let pipe drain
t_0_req <= sv;   t_0_dat <= sd;
snk_tick(kh, i_0_req, i_0_dat, mr);   i_0_ack <= mr;
if (snk_done(kh, ntxn)) begin final_check(); $finish; end
```
Reset: t_0_req=0, i_0_ack=0 (matches C last_ready=0 init).
Source stops at N sent; test ends when sink has drained all N.
`sh`/`kh` are chandles from `src_new`/`snk_new` — multiple instances OK.

## Files

```
poc1/top.v          # DUT B: 3-stage elastic pipeline        ✅
poc1/burb.h         # DPI prototypes (extern "C" guarded)     ✅
poc1/core.c         # PRNG + _BitInt checksum + src/snk + DPI ✅
poc1/tb.sv          # D: clk/rst, wiring, chandles, VCD, $finish ✅
poc1/Makefile       # make vl|qs                              ✅
poc1/core_smoke.c poc1/smoke2_tb.sv   # milestone-1 smoke (can delete)
```

## Build / run

### Verilator  (clang++ for _BitInt)
```make
verilator --binary -j 0 -Wno-fatal --compiler clang \
    -CFLAGS "-std=c++23" -MAKEFLAGS "CXX=clang++ LINK=clang++" \
    -GDW=$(DW) --top-module tb poc1/top.v poc1/tb.sv poc1/core.c -o vsim
./obj_dir/vsim +seed=1 +ntxn=1000 +bubble=20 +backp=20
```
- `--binary` = `--main --exe --build --timing`: runs the SV tb directly
  (clock gen `#`, `$finish`, `$value$plusargs`), no C++ harness.
- clang++ compiles `core.c` (as C++) with `_BitInt`; `extern "C"` keeps DPI
  symbols unmangled.
- 2-state sim: no `x`/`z`. Async `posedge rst` in `top.v` is fine.

### QuestaSim  (DPI-C, vlog auto-compiles C)
```make
export PATH=/home/drom/lscc/diamond/3.14/questasim/bin:$PATH
export LM_LICENSE_FILE=/home/drom/lscc/diamond/3.14/license/license.dat
vlib work
vlog -sv -ccflags "-std=c23" -gDW=$(DW) poc1/top.v poc1/tb.sv poc1/core.c
vsim -c tb +seed=1 +ntxn=1000 +bubble=20 +backp=20 -do "run -all; quit -f"
```
`vlog` auto-compiles the DPI C as C (gcc from PATH) — needs `-std=c23`.

## Waveforms

`tb.sv` calls `$dumpfile("wave.vcd")` + `$dumpvars(0, tb)` unconditionally.
- Verilator: needs `--trace` at build (else `$dumpvars` is a no-op).
- Questa: needs `vsim -voptargs=+acc` (else optimizer strips net visibility
  → VCD has 0 vars). Dumps full hierarchy incl. DUT internals.

## Milestones

1. ✅ **DONE** — smoke tests. Dropped Icarus (no DPI). Locked toolchain:
   DPI-only, clang++/`_BitInt`, `chandle` context, multi-instance.
2. ✅ `top.v` DUT done (elastic pipeline).
3. ✅ **DONE** — `core.c` (xorshift64 + `_BitInt(128)` checksum + src/snk
   ctx + DPI) + `tb.sv` wiring A→top→C via chandles. PASS Verilator+Questa.
4. ✅ **DONE** — bubbles + backpressure active (default 20/20); PASS.
5. ✅ **DONE** — knob/seed sweep: **Verilator == Questa checksum for every
   config**. Same seed + different bubble/backp → same checksum (data stream
   independent of stall timing, as designed). VCD dump on both sims.
6. ✅ **DONE** — `poc2/`: radix2 DUT (`x=a+b, y=a-b`, reqack-generated),
   **2 independent sources + 2 independent sinks** (4 chandles). Verified
   against C reference model `combine_ref`. PASS Verilator+Questa, identical
   checksums, across knob sweep. Confirms chandle instance isolation.
7. (later) VCS.

## poc2 — multi-instance + reference model

`poc2/radix2.v` (generated by `radix2.js` via `reqack`; needs
`node_modules/reqack/rtl/eb15_ctrl.v`). Dataflow: 2 target ports (a,b),
2 initiator ports (x=a+b, y=a-b), 32-bit, **`reset_n` active-low**.

- `poc2/tb.sv` drives 4 DPI instances: `src_new` ×2 (seedA, seedB=seed^0x5eed),
  `snk_new` ×2. Sinks are generic checksum scoreboards.
- Verification: `combine_ref(seedA,seedB,ntxn,op)` in `core.c` regenerates
  the a[n]/b[n] PRNG streams and folds the expected checksum of `a±b`
  (DW-wrapped, matches HW). Sink X == ref(+), Sink Y == ref(-).
- Reuses `../poc1/core.c` + `burb.h` (built with `-DDW=32 -I../poc1`).

**core.c fix from poc2**: data uses `unsigned _BitInt(DW)` (was signed).
For DW<64 the signed cast sign-extended in the checksum while the HW wire
zero-extends → mismatch. poc1 (DW=64) never exposed it. Now consistent.

## Open questions

_All resolved._ DPI-only (Icarus dropped); clang++ for Verilator; `_BitInt`
internal + `chandle` context; knobs = plusargs; DW = compile-time param
(≤64); verification = seeded xorshift64 data + order-sensitive checksum.
