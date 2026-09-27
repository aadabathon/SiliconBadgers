#==============================================================
#  PrimeTime sign-off STA on the routed design (netlist + SPEF from apr.tcl).
#  Run from the work dir:  synopsys-run pt_shell -f <kit>/sta.tcl
#==============================================================
source [file join [file dirname [file normalize [info script]]] config.tcl]
file mkdir reports

set search_path "."
set link_path   [concat * $STD_DB $EXTRA_DBS]

read_verilog $TOP.apr.v
current_design $TOP
if {![link_design]} { puts "ERROR: link_design failed"; exit 1 }

# ICC2 names SPEF files <output>.<corner>_<temp>.spef; take the Cmax (late) one.
set spef [lsort [glob -nocomplain $TOP*.spef]]
puts "SPEF files: $spef"
read_parasitics -format spef [lindex $spef 0]
report_annotated_parasitics -check      > reports/sta_annotation.rpt

read_sdc $TOP.apr.sdc
set_propagated_clock [all_clocks]       ;# real clock tree exists after CTS

update_timing -full
check_timing -verbose                    > reports/sta_check_timing.rpt
report_global_timing                     > reports/sta_global.rpt
report_timing -delay_type max -max_paths 10 -nosplit -input_pins -nets > reports/sta_setup.rpt
report_timing -delay_type min -max_paths 10 -nosplit > reports/sta_hold.rpt
report_constraint -all_violators -nosplit > reports/sta_violators.rpt
report_clock_timing -type skew           > reports/sta_skew.rpt

# Sign-off SDF for gate-level simulation (sim.sh prefers it over ICC2's).
write_sdf -version 3.0 $TOP.pt.sdf

set wns [get_attribute [get_timing_paths -delay_type max] slack]
set whs [get_attribute [get_timing_paths -delay_type min] slack]
puts "STA_RESULT setup_wns=$wns hold_wns=$whs"
puts "=== STA DONE ==="
exit
