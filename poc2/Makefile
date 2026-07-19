# poc2 - multiple independent source/sink instances around radix2 (x=a+b, y=a-b).
#   make gen  # regenerate radix2.v from radix2.js (reqack)
#   make vl   # Verilator + clang++
#   make qs   # QuestaSim
#   make all
#   make clean

SEED  ?= 99
NTXN  ?= 1000
BUBBLE?= 20
BACKP ?= 20
DW     = 32                 # radix2 is fixed 32-bit
PLUS   = +seed=$(SEED) +ntxn=$(NTXN) +bubble=$(BUBBLE) +backp=$(BACKP)

RTL  = radix2.v eb15_ctrl.v
TB   = tb.sv
CORE = ../poc1/core.c        # shared source/sink + combine_ref
INC  = -I../poc1             # burb.h

gen:
	node radix2.js

vl:
	verilator --binary -j 0 -Wno-fatal --trace --compiler clang \
	    -CFLAGS "-std=c++23 -DDW=$(DW) $(INC)" -MAKEFLAGS "CXX=clang++ LINK=clang++" \
	    -GDW=$(DW) --top-module tb $(RTL) $(TB) $(CORE) -o vsim
	./obj_dir/vsim $(PLUS)

QUESTA_BIN = /home/drom/lscc/diamond/3.14/questasim/bin
QUESTA_LIC = /home/drom/lscc/diamond/3.14/license/license.dat
qs:
	PATH=$(QUESTA_BIN):$$PATH LM_LICENSE_FILE=$(QUESTA_LIC) sh -c '\
	  vlib work && \
	  vlog -sv -ccflags "-std=c23 -DDW=$(DW) $(INC)" $(RTL) $(TB) $(CORE) && \
	  vsim -c tb -voptargs=+acc -gDW=$(DW) $(PLUS) -do "run -all; quit -f"'

all: vl qs

clean:
	rm -rf obj_dir work transcript *.vvp *.vpi *.o vsim modelsim.ini *.vcd *.wlf
.PHONY: gen vl qs all clean
