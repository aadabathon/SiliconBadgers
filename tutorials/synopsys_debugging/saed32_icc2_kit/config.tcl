#==============================================================
#  Project config — the ONLY file you edit per RTL project.
#  Sourced by synth.tcl (dc_shell) and apr.tcl (icc2_shell).
#==============================================================

# --- Design --------------------------------------------------
set TOP         cpu16_core
set RTL_DIR     /userspace/ashebani/RTL_sandbox/16_Bit_CPU/rtl
# Order matters: packages first.
set RTL_FILES   {cpu16_isa.sv cpu16_regfile.sv cpu16_alu.sv cpu16_datapath.sv cpu16_control_fsm.sv cpu16_core.sv}
set CLK_PORT    clk
set CLK_PERIOD  3.0       ;# ns
set IO_DELAY    0.5       ;# ns, input/output delay vs clock
set CORE_UTIL   0.6       ;# floorplan core utilization
# Die-to-core gap. Keep it a multiple of the track pitches (M1/M2 0.152 ... M9 2.432)
# so rows and tracks share an origin. 4.864 = 2 x 2.432. (This does NOT remove the
# ~100 VIA1 off-grid DRCs; those come from SAED32 M1 pins sitting off the track grid.)
set CORE_OFFSET 4.864
set MAX_LAYER   M7        ;# top routing layer (M8/M9 left for power)

# --- Kit (SAED32 EDK, new CAE layout as of Fall 2026) --------
set EDK         /srv/auto/apps/saed32_edk/2023
set CORNER      ss0p95v125c
set PROC_NUM    0.99
set VOLT        0.95
set TEMP        125
set STD_DB      $EDK/lib/stdcell_rvt/db_nldm/saed32rvt_$CORNER.db
set TLUP_DIR    $EDK/tech/star_rcxt
set CELL_GDS    $EDK/lib/stdcell_rvt/gds/saed32nm_rvt_oa.gds

# --- NDM built by build_ndm.tcl (lm_shell) -------------------
set KIT_DIR     [file dirname [file normalize [info script]]]
set NDM_DIR     $KIT_DIR/ndm
set STD_NDM     $NDM_DIR/saed32rvt.ndm

# Optional hard macros (e.g. SAED32 SRAMs). Leave empty if none.
#   set EXTRA_DBS  [list $EDK/lib/sram/db_nldm/saed32sram_$CORNER.db]
#   set EXTRA_NDMS [list $NDM_DIR/saed32sram.ndm]
set EXTRA_DBS   {}
set EXTRA_NDMS  {}
