#!/bin/bash
# VCS simulation: RTL (+coverage), routed gate netlist, routed netlist + SDF.
# Runs INSIDE the container (run.sh calls: synopsys-run bash sim.sh). cwd = work dir.
# Pass = CPU16_SMOKE_PASS in every log AND identical per-cycle bus traces.
KIT="$(cd "$(dirname "$0")" && pwd)"
cfg() { awk -v k="$1" '$1=="set" && $2==k {sub(/^[ \t]*set[ \t]+[^ \t]+[ \t]+/,""); sub(/[ \t]*;#.*$/,""); gsub(/[{}]/,""); print; exit}' "$KIT/config.tcl"; }
TOP=$(cfg TOP); RTL_DIR=$(cfg RTL_DIR); RTL_FILES=$(cfg RTL_FILES)
TB="${TB:-$KIT/tb/cpu16_smoke_tb.sv}"
TB_EXTRA="${TB_EXTRA:-$RTL_DIR/Sram.sv}"   # testbench-side models (memory), same for all runs
CELLS=/srv/auto/apps/saed32_edk/2023/lib/stdcell_rvt/verilog/saed32nm.v
RTL=(); for f in $RTL_FILES; do RTL+=("$RTL_DIR/$f"); done
export VERDI_HOME="$(dirname "$(dirname "$(command -v verdi)")")"
SDF="../$TOP.pt.sdf"; [[ -f $TOP.pt.sdf ]] || SDF="../$TOP.sdf"   # PrimeTime SDF if present
mkdir -p sim && cd sim || exit 1
COMMON=(-full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -top tb)

vcs "${COMMON[@]}" -cm line+cond+tgl+branch+fsm +define+FSDB "${RTL[@]}" "$TB_EXTRA" "$TB" -o simv_rtl -Mdir=csrc_rtl > compile_rtl.log 2>&1
./simv_rtl -cm line+cond+tgl+branch+fsm +TRACE=trace_rtl.txt > sim_rtl.log 2>&1
urg -full64 -dir simv_rtl.vdb -report coverage_report -format both > urg.log 2>&1

# Gate level: no timing (zero-delay functional) ...
vcs "${COMMON[@]}" +nospecify +notimingcheck "$CELLS" "../$TOP.apr.v" "$TB_EXTRA" "$TB" -o simv_gate -Mdir=csrc_gate > compile_gate.log 2>&1
./simv_gate +TRACE=trace_gate.txt > sim_gate.log 2>&1

# ... and with routed-parasitic delays from ICC2 (SDF) + timing checks.
vcs "${COMMON[@]}" +neg_tchk -sdf max:tb.dut:"$SDF" "$CELLS" "../$TOP.apr.v" "$TB_EXTRA" "$TB" -o simv_sdf -Mdir=csrc_sdf > compile_sdf.log 2>&1
./simv_sdf +TRACE=trace_sdf.txt > sim_sdf.log 2>&1

# Negative test: the checker must notice an injected stuck-at-0 on mem_wdata[0].
./simv_gate +TRACE=trace_neg.txt +INJECT_FAILURE > sim_neg.log 2>&1

for r in rtl gate sdf; do echo "SIM_$r: $(grep -hE 'CPU16_SMOKE_(PASS|FAIL)' sim_$r.log || echo 'NO MARKER (see sim/compile_'$r'.log, sim/sim_'$r'.log)')"; done
cmp -s trace_rtl.txt trace_gate.txt && echo "TRACE rtl==gate: MATCH" || echo "TRACE rtl==gate: DIFF"
cmp -s trace_rtl.txt trace_sdf.txt  && echo "TRACE rtl==sdf:  MATCH" || echo "TRACE rtl==sdf:  DIFF"
cmp -s trace_rtl.txt trace_neg.txt  && echo "NEGATIVE: NOT DETECTED (checker is blind!)" || echo "NEGATIVE: injected fault detected (traces differ, as expected)"
echo "ACTIVITY: $(awk '{print $2}' trace_rtl.txt | sort -u | wc -l) distinct addresses, $(awk '$4==1' trace_rtl.txt | wc -l) write cycles"
echo "SDF used: $SDF"
echo "SDF annotation: $(grep -cE 'SDFCOM_(UHICD|INPD|NICD)|Warning-\[SDFCOM' compile_sdf.log) SDF warnings; timing violations: $(grep -c 'Timing violation' sim_sdf.log)"
echo "=== SIM DONE ==="
