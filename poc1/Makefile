# burbulator PoC - DPI-C smoke test (Icarus dropped: no DPI-C support).
#   make vl   # Verilator + clang++ (C23 _BitInt compiles as C++)
#   make qs   # QuestaSim (vlog auto-compiles C with -std=c23)
#   make all
#   make clean
#
# Core C uses C23 _BitInt internally, chandle for per-instance context.
# g++ does NOT support _BitInt -> Verilator must use clang++.

SEED  ?= 99
NTXN  ?= 1000
BUBBLE?= 20
BACKP ?= 20
DW    ?= 64
PLUS   = +seed=$(SEED) +ntxn=$(NTXN) +bubble=$(BUBBLE) +backp=$(BACKP)

RTL  = top.v
TB   = tb.sv
CORE = core.c

# --- Verilator: DPI-C. clang++ so _BitInt works; --binary runs SV tb. ---
vl:
	verilator --binary -j 0 -Wno-fatal --trace --compiler clang \
	    -CFLAGS "-std=c++23 -DDW=$(DW)" -MAKEFLAGS "CXX=clang++ LINK=clang++" \
	    -GDW=$(DW) --top-module tb $(RTL) $(TB) $(CORE) -o vsim
	./obj_dir/vsim $(PLUS)

# --- QuestaSim: DPI-C, vlog auto-compiles C (needs -std=c23 for _BitInt). ---
QUESTA_BIN = /home/drom/lscc/diamond/3.14/questasim/bin
QUESTA_LIC = /home/drom/lscc/diamond/3.14/license/license.dat
qs:
	PATH=$(QUESTA_BIN):$$PATH LM_LICENSE_FILE=$(QUESTA_LIC) sh -c '\
	  vlib work && \
	  vlog -sv -ccflags "-std=c23 -DDW=$(DW)" $(RTL) $(TB) $(CORE) && \
	  vsim -c tb -voptargs=+acc -gDW=$(DW) $(PLUS) -do "run -all; quit -f"'

all: vl qs

clean:
	rm -rf obj_dir work transcript *.vvp *.vpi *.o vsim modelsim.ini *.vcd *.wlf
.PHONY: vl qs all clean
