#==============================================================
#  Formality logic equivalence: RTL (reference) vs a gate netlist (implementation).
#  Run from the work dir:  synopsys-run fm_shell -f <kit>/lec.tcl
#  IMPL env var picks the netlist: synth (default) -> netlist/$TOP.v, apr -> $TOP.apr.v
#==============================================================
source [file join [file dirname [file normalize [info script]]] config.tcl]
file mkdir reports
set which [expr {[info exists env(IMPL)] ? $env(IMPL) : "synth"}]
set netlist [expr {$which eq "apr" ? "$TOP.apr.v" : "netlist/$TOP.v"}]

# DC's guidance file lets Formality follow retiming/ungrouping/renaming.
if {[file exists default.svf]} { set_svf default.svf }

read_db [concat $STD_DB $EXTRA_DBS]
read_sverilog -r [lmap f $RTL_FILES {file join $RTL_DIR $f}]
set_top r:/WORK/$TOP

read_verilog -i $netlist
set_top i:/WORK/$TOP

match
report_unmatched_points > reports/lec_${which}_unmatched.rpt
set ok [verify]
report_failing_points   > reports/lec_${which}_failing.rpt
puts "LEC_RESULT impl=$which netlist=$netlist verified=$ok"
puts "=== LEC DONE ==="
exit
