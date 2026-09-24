#==============================================================
#  Generic ICC2 APR: netlist+SDC -> floorplan -> PG -> place -> CTS -> route -> GDS
#  Run from the synth work dir:  synopsys-run icc2_shell -f <kit>/apr.tcl
#==============================================================
source [file join [file dirname [file normalize [info script]]] config.tcl]
set_host_options -max_cores 4
file mkdir reports

set REFS [concat [list $STD_NDM] $EXTRA_NDMS]
if {[file exists $TOP.dlib]} { file delete -force $TOP.dlib }
create_lib $TOP.dlib -ref_libs $REFS -use_technology_lib $STD_NDM
read_parasitic_tech -tlup $TLUP_DIR/saed32nm_1p9m_Cmax.tluplus -layermap $TLUP_DIR/saed32nm_tf_itf_tluplus.map -name Cmax
read_parasitic_tech -tlup $TLUP_DIR/saed32nm_1p9m_Cmin.tluplus -layermap $TLUP_DIR/saed32nm_tf_itf_tluplus.map -name Cmin

read_verilog netlist/$TOP.v -top $TOP
link_block
connect_pg_net -automatic

#--- single-corner MCMM ---------------------------------------
remove_modes -all; remove_corners -all; remove_scenarios -all
create_mode func
create_corner $CORNER
create_scenario -mode func -corner $CORNER -name func_$CORNER
current_scenario func_$CORNER
read_sdc netlist/$TOP.sdc
set_parasitic_parameters -corners $CORNER -late_spec Cmax -early_spec Cmin
set_process_number -corners $CORNER $PROC_NUM
set_voltage $VOLT -corners $CORNER -object_list VDD
set_voltage 0.00  -corners $CORNER -object_list VSS
set_temperature   -corners $CORNER $TEMP
set_scenario_status func_$CORNER -active true -setup true -hold true -leakage_power true -dynamic_power true

#--- routing layers (MRDL has no direction in the SAED32 tf) ---
set_attribute [get_layers {M1 M3 M5 M7 M9}] routing_direction horizontal
set_attribute [get_layers {M2 M4 M6 M8 MRDL}] routing_direction vertical
set_ignored_layers -max_routing_layer $MAX_LAYER

#--- floorplan + pins -----------------------------------------
initialize_floorplan -core_utilization $CORE_UTIL -core_offset $CORE_OFFSET
place_pins -self

#--- power: M1 followpin rails + M6/M7 mesh -------------------
connect_pg_net -net VDD [get_pins -hierarchical */VDD]
connect_pg_net -net VSS [get_pins -hierarchical */VSS]
create_pg_std_cell_conn_pattern rail -layers {M1} -rail_width 0.06
set_pg_strategy rails -core -pattern {{name: rail} {nets: VDD VSS}}
compile_pg -strategies rails
create_pg_mesh_pattern mesh -layers {{{vertical_layer: M6} {width: 0.4} {spacing: interleaving} {pitch: 10}} {{horizontal_layer: M7} {width: 0.4} {spacing: interleaving} {pitch: 10}}}
set_pg_strategy meshs -core -pattern {{name: mesh} {nets: VDD VSS}}
compile_pg -strategies meshs

#--- implementation -------------------------------------------
place_opt
clock_opt
route_auto
route_opt
route_detail -incremental true -initial_drc_from_input true -max_number_iterations 30

#--- fillers: close the rows (N-well/implant continuity) -------
create_stdcell_fillers -lib_cells [get_lib_cells */SHFILL*_RVT]
connect_pg_net -automatic
remove_stdcell_fillers_with_violation

#--- signoff-ish reports --------------------------------------
check_routes                          > reports/apr_check_routes.rpt
report_qor -summary                   > reports/apr_qor.rpt
report_timing -max_paths 5            > reports/apr_timing.rpt
report_timing -delay_type min         > reports/apr_hold.rpt
report_utilization                    > reports/apr_util.rpt
report_clock_qor -type summary        > reports/apr_clock.rpt
report_power                          > reports/apr_power.rpt

save_block
save_lib
#--- handoff to PrimeTime (sta.tcl) ---------------------------
write_verilog -exclude {pg_objects physical_only_cells} $TOP.apr.v
write_parasitics -output $TOP
write_sdc -output $TOP.apr.sdc
write_sdf $TOP.sdf
write_gds -hierarchy all -long_names -merge_files $CELL_GDS $TOP.gds
puts "=== APR DONE ==="
exit
