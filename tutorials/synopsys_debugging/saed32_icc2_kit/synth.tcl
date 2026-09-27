#==============================================================
#  Generic DC synthesis against the SAED32 kit .db (cells named *_RVT,
#  so the netlist matches the NDM directly — no renaming needed).
#  Run from a work dir:  synopsys-run dc_shell -f <kit>/synth.tcl
#==============================================================
source [file join [file dirname [file normalize [info script]]] config.tcl]
file mkdir reports netlist

set target_library $STD_DB
set link_library   [concat * $STD_DB $EXTRA_DBS]
set search_path    [concat $search_path $RTL_DIR]

analyze -format sverilog $RTL_FILES
elaborate $TOP
current_design $TOP
if {![link]} { echo "ERROR: link failed"; exit 1 }

set in_no_clk [remove_from_collection [all_inputs] [get_ports $CLK_PORT]]
create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT]
set_clock_uncertainty 0.15 [get_clocks clk]
set_input_delay  $IO_DELAY -clock clk $in_no_clk
set_output_delay $IO_DELAY -clock clk [all_outputs]
set_driving_cell -lib_cell INVX2_RVT $in_no_clk
set_load [expr {5 * [load_of saed32rvt_$CORNER/INVX2_RVT/A]}] [all_outputs]

compile_ultra

report_qor                        > reports/synth_qor.rpt
report_timing -max_paths 5        > reports/synth_timing.rpt
report_area                       > reports/synth_area.rpt
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output netlist/$TOP.v
write_sdc                                 netlist/$TOP.sdc
echo "=== SYNTH DONE ==="
exit
