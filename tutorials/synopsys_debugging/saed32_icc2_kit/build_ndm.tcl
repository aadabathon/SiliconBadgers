#==============================================================
#  Build ICC2 NDM reference libs for SAED32 from LEF + .db.
#  Run once:  synopsys-run icc2_lm_shell -f build_ndm.tcl
#
#  Why not the kit's own files:
#   - lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef is a TECH-ONLY LEF (0 MACROs).
#     The real cell LEF (350 MACROs) is buried under
#     lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/lef/.
#   - The prebuilt 2022 lib/stdcell_*/ndm/*.ndm are from a different cell
#     release (1.824um rows, 0.32x2.88 site) and their timing is unusable in
#     ICC2 X-2025.06 (every arc evaluates to "??").
#   - generate_frame_from_mw still fails even with Milkyway on PATH.
#==============================================================
set KIT  [file dirname [file normalize [info script]]]
set E23  /srv/auto/apps/saed32_edk/2023
set TF   $E23/tech/milkyway/saed32nm_1p9m_mw.tf   ;# stock tf parses fine in lm_shell
set OUT  $KIT/ndm
file mkdir $OUT

# name  cell-LEF  db-glob
set LIBS [list \
  saed32rvt  $E23/lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef \
             "$E23/lib/stdcell_rvt/db_nldm/saed32rvt_{ss0p95v125c,tt1p05v25c,ff1p16vn40c}.db" \
  saed32sram $E23/lib/sram/lef/saed32sram.lef \
             "$E23/lib/sram/db_nldm/saed32sram_{ss0p95v125c,tt1p05v25c,ff1p16vn40c}.db" \
]

foreach {name lef dbs} $LIBS {
  create_workspace -technology $TF ${name}_ws
  read_lef -include cell $lef
  read_db [glob $dbs]
  if {[catch {check_workspace} m]} { puts "NDM_FAIL $name check: $m"; remove_workspace; continue }
  if {[catch {commit_workspace -force -output $OUT/$name.ndm} m]} { puts "NDM_FAIL $name commit: $m" } else { puts "NDM_OK $OUT/$name.ndm" }
  catch {remove_workspace}
}
exit
