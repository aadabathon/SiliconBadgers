# Synopsys on UW–Madison CAE: the complete guide

**RTL → simulation → synthesis → equivalence → place & route → sign-off timing → gate-level sim → GDS**

For: Adam (and anyone else on CAE Linux) · Written 2026-09-24 · Verified on `linux-2001` and `linux-2637`

> **How this guide was built.** Anything marked ✅ was run end to end on CAE during this work, with logs.
> The Adam16 CPU (`cpu16_core`, 1,852 cells) went through every stage in **5 min 42 s** from a clean start, with **0 errors in every log**.
> Anything marked 📘 comes from Abhinav Nandwani's CAE lab handouts (23 Sep 2026) and was not re-run here. That is mostly the GUI walkthroughs, which are for a human to do in Guacamole.

---

## Contents

0. [The 60-second version](#0-the-60-second-version)
1. [Getting onto CAE](#1-getting-onto-cae)
2. [How software runs on CAE now (modules + containers)](#2-how-software-runs-on-cae-now)
3. [The flow at a glance](#3-the-flow-at-a-glance)
4. [The kit: one command, RTL to GDS](#4-the-kit-one-command-rtl-to-gds)
5. [Tool by tool](#5-tool-by-tool)
   - 5.1 [VCS, Verdi, URG: simulation, debug, coverage](#51-vcs-verdi-urg)
   - 5.2 [Design Compiler and Design Vision: synthesis](#52-design-compiler--design-vision)
   - 5.3 [Formality: equivalence checking](#53-formality)
   - 5.4 [ICC2 Library Manager: building the NDM reference library](#54-icc2-library-manager-building-the-ndm)
   - 5.5 [IC Compiler II: place and route](#55-ic-compiler-ii-place--route)
   - 5.6 [PrimeTime: sign-off timing](#56-primetime-sign-off-sta)
   - 5.7 [Gate-level simulation with SDF](#57-gate-level-simulation-with-sdf)
6. [The SAED32 kit: map of what's real and what's a trap](#6-the-saed32-kit-map)
7. [Adapting the flow to your own RTL](#7-adapting-the-flow-to-your-own-rtl)
8. [Troubleshooting encyclopedia (every error we hit)](#8-troubleshooting-encyclopedia)
9. [Known limitations and open items](#9-known-limitations-and-open-items)
10. [Appendix: handout lab (`sb_flop`) quick reference, links](#10-appendix)

---

## 0. The 60-second version

```bash
ssh <netid>@best-linux.cae.wisc.edu          # or use a Guacamole terminal
cd ~/synopsys_debugging/saed32_icc2_kit
vi config.tcl                                  # TOP, RTL_DIR, RTL_FILES, CLK_PORT, CLK_PERIOD
./run.sh ~/synopsys_debugging/runs/myrun       # runs every stage; prints a verdict line for each
```

`run.sh` loads the modules itself and runs each tool through `synopsys-run`.
You can also run a single stage: `./run.sh <dir> ndm|synth|apr|sta|lec|sim|shot`.

**What a good run prints** (✅ Adam16, 333 MHz target, slow corner ss0p95v125c):

```
NDM_OK .../ndm/saed32rvt.ndm            NDM_OK .../ndm/saed32sram.ndm
=== SYNTH DONE ===                      === APR DONE ===
STA_RESULT setup_wns=0.004199 hold_wns=0.060208
LEC_RESULT impl=synth ... verified=1    LEC_RESULT impl=apr ... verified=1
SIM_rtl/gate/sdf: CPU16_SMOKE_PASS      TRACE rtl==gate: MATCH   TRACE rtl==sdf: MATCH
NEGATIVE: injected fault detected       SDF annotation: 0 SDF warnings; timing violations: 0
```

To look at the layout (you, in a GUI session; see §5.5.8):

```bash
module load synopsys/suite; cd ~/synopsys_debugging/runs/myrun; synopsys-run icc2_shell
icc2_shell> open_lib cpu16_core.dlib ; open_block cpu16_core ; start_gui
```

---

## 1. Getting onto CAE

| Way in | When to use it | Notes |
|---|---|---|
| **Guacamole** 📘 `https://guacamole.cae.wisc.edu` | Any GUI (Verdi, Design Vision, ICC2) | Log in with your UW NetID twice: web SSO + MFA, then the Linux login. Then Apps → Terminal. Don't SSH back into CAE from inside it. [KB 163323](https://kb.wisc.edu/cae/163323) |
| **SSH** `ssh <netid>@best-linux.cae.wisc.edu` | Batch runs, scripts | The handout says `best-tux`; CAE's Aug-2026 KB changes point to `best-linux`. Your home dir is shared across hosts. |
| **MobaXterm** SSH (built-in X server) | GUIs without the browser | `echo $DISPLAY` must be non-empty. The `synopsys-run` wrapper forwards `$DISPLAY` and `/tmp/.X11-unix` into the container. |

- Your home is **`/userspace/<netid>`**, not `/home/<netid>`.
- To log out properly, use the desktop's system menu. 📘 Closing the browser leaves the session alive for about 2 hours.

---

## 2. How software runs on CAE now

CAE changed this in **Fall 2026**. The old `/opt/cae/bin/...` and `/cae/apps/data/...` paths **no longer exist**.
If you type `icc2_shell` without setting up first, you hit a stub in `/usr/local/cae/bin/` that prints *"WARNING: icc2_shell was invoked without loading the appropriate modules first!"*.

### 2.1 The two-step pattern

```bash
module load synopsys/suite        # 1. Lmod: sets PATH, license (27180@synopsys.license.cae.wisc.edu), $SYNOPSYS
synopsys-run                      # 2. enter the Singularity container (AlmaLinux 8.10); prompt becomes "synopsys>"
synopsys> dc_shell                # tools run inside the container
```

- **Non-interactive** ✅: `synopsys-run <command> [args]` runs one command in the container and exits.
  - Examples: `synopsys-run icc2_shell -f script.tcl > run.log 2>&1 < /dev/null`, or `synopsys-run bash -c "…"`.
  - Environment variables pass through into the container. The kit relies on this.
- **Order matters:** load the module *before* `synopsys-run`, in *every* new shell.
- Some `module avail` highlights:
  - `synopsys/suite/2026` is a meta-module that loads about 20 tools.
  - Single tools: `synopsys/iccompiler2/2026.03`, `synopsys/milkyway/2026.03`, `synopsys/primetime/2026.03`.
  - PDKs: `saed32_edk/2023` (sets `$SAED32_28_PDK`), `asap7pdk`, `gpdk045`, `ncsu` (FreePDK45).
  - Also: `cadence/innovus/211`.
- The modulefiles themselves are readable at `/srv/auto/modules/modulefiles/`. `cat` them to see exactly what they set.

### 2.2 Where things live ✅

| What | Path |
|---|---|
| Synopsys installs | `/srv/auto/apps/synopsys-2026/<tool>/<version>/` |
| Versions | **ICC2 / Library Manager X-2025.06-SP3** (older than the rest). DC, PrimeTime, Formality, VCS, Verdi, URG, Milkyway: **Y-2026.03** |
| Container image | `/srv/auto/apps/synopsys-2026/snps_container/2.1/data/almalinux8.sif` |
| SAED32 EDK (readable) | `/srv/auto/apps/saed32_edk/2023` (and `2022`) |
| SAED32 PDK | `/srv/auto/apps/saed32_pdk/*`: **permission denied** for students. Same for `saed90_*` and `opencell-pdk`. |

### 2.3 Environment gotchas (each one cost real time) ✅

| Symptom | Cause | Fix |
|---|---|---|
| `FATAL: "icc2_shell": executable file not found in $PATH` from `synopsys-run` | The module wasn't loaded **in this shell**. `module load … \| tail` runs in a *subshell* because of the pipe. | Run `module load synopsys/suite >/dev/null 2>&1` on its own line |
| A script's `module load` silently does nothing | `set -u` (nounset) breaks Lmod's init scripts | Don't use `set -u` in scripts that call `module`. In non-login scripts, `source /etc/profile.d/95-lmod.sh` first. |
| `Xvfb: 183: Syntax error: "(" unexpected` | The Verdi module puts a broken `Xvfb` script on PATH | `env -i PATH=/usr/bin:/bin Xvfb :N …` |
| `python3` inside the container is odd | It resolves to **Custom Compiler's bundled Python** (`customcompiler/Y-2026.03/bin/python3`) | Use `/usr/bin/python3` explicitly if it matters |
| `git` not found inside the container | The container has no git | Run git on the host |
| Exit code 0 but the test failed | 📘✅ VCS returns 0 even on `$fatal` | Always grep for a **positive pass marker** and for `^Error\|^Fatal` |
| Tool drops to an interactive prompt at the end of `-f script.tcl` | A Tcl error stopped the script; the tool then reads stdin | Redirect `< /dev/null` and grep the log for `^Error`. Read the **first** error. |

---

## 3. The flow at a glance

```
            ┌────────── functional ──────────┐        ┌──────── implementation ────────┐
 RTL (.sv) ─┤ VCS sim  → Verdi waves          │        │                                │
            │ URG coverage                    │        │ Library Manager: tf+LEF+.db    │
            └─────────────────────────────────┘        │        → saed32rvt.ndm         │
     │                                                  └──────────────┬─────────────────┘
     ▼                                                                 ▼
 Design Compiler ──► netlist/$TOP.v + .sdc ──────────► IC Compiler II: floorplan → PG → place_opt
  (kit .db)              │                                  → clock_opt → route → fillers
                         ▼                                         │
                   Formality: RTL ≡ synth netlist         $TOP.apr.v, SPEF, SDC, GDS, .dlib
                                                                   │
                         ┌─────────────────────────────────────────┼────────────────────┐
                         ▼                                         ▼                    ▼
               Formality: RTL ≡ routed netlist        PrimeTime: sign-off STA   VCS gate + SDF sim
                                                        → $TOP.pt.sdf ──────────────►  (traces must match RTL)
```

**Checks every stage must pass before you move on:**

| Stage | Pass means (✅ Adam16 value) |
|---|---|
| RTL sim | Pass marker, no X on the bus, non-trivial activity (415 addresses, 79 stores) |
| Coverage | You know what's *not* covered (DUT: line 81%, toggle 95%, FSM 46%; see §5.1) |
| Synthesis | `link` OK, positive slack (+0.08 ns), no unmapped/GTECH cells |
| LEC (synth) | `Verification SUCCEEDED` (232/232 compare points) |
| NDM | `Workspace check succeeded!`, **294** frames |
| APR | 0 open nets, timing met in ICC2, DRCs understood (189; see §9) |
| STA (PrimeTime) | setup WNS ≥ 0 (+0.004), hold WNS ≥ 0 (+0.060), SPEF fully annotated (1622/1622) |
| LEC (routed) | `Verification SUCCEEDED` |
| Gate + SDF sim | Same trace as RTL, 0 timing violations, 0 SDF warnings |

---

## 4. The kit: one command, RTL to GDS

Location: `~/synopsys_debugging/saed32_icc2_kit/`

| File | Tool | What it does |
|---|---|---|
| `config.tcl` | — | **The only file you edit.** Design name, RTL list, clock, utilization, corner, paths. |
| `run.sh` | bash | Loads modules and runs each stage in the container with its own log. Prints verdict lines. |
| `build_ndm.tcl` | `icc2_lm_shell` | Builds `ndm/saed32rvt.ndm` (std cells) and `ndm/saed32sram.ndm` (SRAM macros). Runs once. |
| `synth.tcl` | `dc_shell` | RTL → `netlist/$TOP.v` + `.sdc` using the **kit** `.db` (cells named `*_RVT`) |
| `apr.tcl` | `icc2_shell` | Floorplan, power grid, place, CTS, route, fillers. Writes `.dlib`, `$TOP.apr.v`, SPEF, SDC, SDF, GDS. |
| `sta.tcl` | `pt_shell` | Sign-off STA on routed netlist + SPEF. Writes `$TOP.pt.sdf`. |
| `lec.tcl` | `fm_shell` | RTL vs synth netlist (`IMPL=synth`) or RTL vs routed netlist (`IMPL=apr`) |
| `sim.sh` + `tb/cpu16_smoke_tb.sv` | `vcs`, `urg` | RTL sim with coverage; gate-level sim; gate-level + SDF sim; a negative test; trace compare |
| `screenshot.tcl` | `icc2_shell` GUI | Headless layout PNG via Xvfb. **Only runs as `run.sh <dir> shot`**, never as part of `all`. |

**Work-directory contents after `all`:**
- Logs: `ndm.log synth.log apr.log sta.log lec_*.log`
- `reports/`: `synth_* apr_* sta_* lec_*`
- `netlist/`, `cpu16_core.dlib/` (ICC2 database)
- `cpu16_core.{apr.v, apr.sdc, Cmax_125.spef, Cmin_125.spef, sdf, pt.sdf, gds}`
- `sim/` (simv binaries, traces, `coverage_report/dashboard.html`, `smoke.fsdb`)

**Licensing.** SAED32 is licensed educational IP. Never commit or copy off-CAE any `.db .lib .lef .tf .tluplus .ndm .gds`, the mapped netlist, or the `.dlib`.
`.gitignore` already excludes `ndm/ runs/ *.gds *.db *.lef *.ndm *.dlib/`. Scripts, reports and screenshots are fine to share.

---

## 5. Tool by tool

### 5.1 VCS, Verdi, URG

**VCS compile + run** ✅ (from `sim.sh`):

```bash
export VERDI_HOME="$(dirname "$(dirname "$(command -v verdi)")")"   # needed for FSDB dumping
vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -top tb \
    -cm line+cond+tgl+branch+fsm +define+FSDB \
    <rtl files in package-first order> <tb files> -o simv_rtl -Mdir=csrc_rtl > compile_rtl.log 2>&1
./simv_rtl -cm line+cond+tgl+branch+fsm +TRACE=trace_rtl.txt > sim_rtl.log 2>&1
urg -full64 -dir simv_rtl.vdb -report coverage_report -format both > urg.log 2>&1
```

- **`-top tb`**: the simulation top is the testbench, not the design. A wrong top can "pass" without ever applying your stimulus. 📘
- `-debug_access+all -kdb` keeps what Verdi needs to show source. `-cm …` enables code coverage; it doesn't invent functional coverage goals.
- `-Mdir=` gives each build its own scratch dir, so you can keep several `simv`s side by side.
- `urg -format both` writes HTML (`dashboard.html`) **and** text (`dashboard.txt`, `hierarchy.txt`), and the text versions are greppable.
- Always stop after a failed compile. The shell won't stop for you. Check `compile.log` first, then `sim.log`.

**Writing a testbench that proves something** ✅. This is what `tb/cpu16_smoke_tb.sv` teaches:
1. **Use the real memory model.** Adam16's FSM has a wait state (`S_IF1`) for a **1-cycle synchronous SRAM read**. An async-read memory model gave a *vacuous* pass: the CPU looped between 2 addresses and the traces "matched" anyway. The tb now instantiates `SramSBC` from `rtl/Sram.sv`.
2. **Check activity, not just "no errors".** The tb prints `ACTIVITY: 415 distinct addresses, 79 write cycles`. If it says 2 addresses, your test is broken.
3. **Constrain random stimulus.** Memory is filled with fixed-seed random *non-control-flow* opcodes (ALU/ADDI/ANDI/LEA/LD/ST/LDR/STR), so the PC walks linearly.
4. **Negative test.** `+INJECT_FAILURE` forces `dut.mem_wdata[0]` to 0. The trace must then **differ** (`NEGATIVE: injected fault detected`). If it doesn't, the checker is blind.
5. **Sample away from edges.** The tb samples at `negedge` and releases reset a quarter period after an edge, so the same tb works for zero-delay and SDF-delay netlists.

**Coverage reading** ✅ (Adam16 DUT): line 80.9%, cond 81.6%, toggle 94.5%, **FSM 46%**, branch 72.9%.
The FSM hole is expected: the smoke test deliberately never issues BR/JMP/JSR/RET/TRAP.
Always write down the *scope* (DUT vs. `tb` totals, which include testbench and UVM code) along with the percentage. 📘

**Verdi** 📘 (GUI, in Guacamole): `cd <run>/sim; verdi -ssf smoke.fsdb`.
- Hierarchy pane: `tb` → `dut`.
- nWave: Signal → Get Signals → pick signals → Apply → OK, then View → Zoom → Zoom All.
- File → Save Signal (`.rc`) saves the view.
- The value column is at the **cursor time**, not end-of-sim.
- Only open an FSDB with the build that produced it.

**Coverage HTML** 📘: `firefox <run>/sim/coverage_report/dashboard.html` (runs on CAE), then hierarchy → `tb` → `dut`.

### 5.2 Design Compiler / Design Vision

**Batch synthesis** ✅ (from `synth.tcl`):

```tcl
set target_library $STD_DB                                  ;# cells DC may map to
set link_library   [concat * $STD_DB $EXTRA_DBS]           ;# how references resolve ("*" = designs in memory)
set search_path    [concat $search_path $RTL_DIR]
analyze -format sverilog $RTL_FILES                         ;# packages FIRST
elaborate $TOP ; current_design $TOP
if {![link]} { exit 1 }                                     ;# unresolved reference = stop
create_clock -name clk -period $CLK_PERIOD [get_ports $CLK_PORT]
set_clock_uncertainty 0.15 [get_clocks clk]
set_input_delay  $IO_DELAY -clock clk <inputs minus clk>
set_output_delay $IO_DELAY -clock clk [all_outputs]
set_driving_cell -lib_cell INVX2_RVT <inputs> ; set_load [expr 5*[load_of saed32rvt_$CORNER/INVX2_RVT/A]] [all_outputs]
compile_ultra
report_qor ; report_timing ; report_area
change_names -rules verilog -hierarchy                      ;# netlist names that ICC2/VCS/Formality parse cleanly
write -format verilog -hierarchy -output netlist/$TOP.v ; write_sdc netlist/$TOP.sdc
```

- **Use the kit `.db`:** `/srv/auto/apps/saed32_edk/2023/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db`.
  - Its cells are named `DFFX1_RVT` etc., which match the LEF, the NDM and the Verilog sim models.
  - Adam's old private `.db` (`~/RTL_sandbox/libraries/`) had *plain* names (`DFFX1`). That forced the `sed 's/_RVT//'` hack for simulation and broke ICC2 linking. Don't use it.
- **Corners** (`saed32rvt_<corner>.db`): `ss0p95v125c` (slow and hot, the setup sign-off corner used here), `tt1p05v25c` (the handouts' teaching corner), `ff1p16vn40c` (fast; hold). The file name is also the library name.
- `compile_ultra` writes `default.svf`. **Keep it**: Formality uses it (§5.3).
- A GTECH or unmapped cell in the netlist means `target_library` didn't load. `synth.tcl` always links first and checks.
- Adam16 ✅: 1,852 cells, 5,294 µm² (area report includes a wireload estimate), slack +0.08 ns at 3.0 ns.

**Design Vision** 📘 (GUI; launch `design_vision` in the synth run dir; the bottom line is a Tcl prompt):

```tcl
set_app_var target_library [list /srv/auto/apps/saed32_edk/2023/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db]
set_app_var link_library   [concat * $target_library]
read_ddc mapped.ddc ; current_design <top> ; link ; read_sdc constraints.sdc ; check_design
```

- Schematic → New Schematic View, then double-click the box to expand.
- Timing → Report Timing Path gives the same data as `report_timing` in the console.
- The kit writes Verilog + SDC. Add `write -format ddc -hierarchy -output netlist/$TOP.ddc` to `synth.tcl` if you want a DDC.
- Don't feed a DC 2026.03 DDC to ICC2 2025.06. Give ICC2 the Verilog netlist. 📘

**Reading timing** (DC, ICC2 and PT share the same format):
- Find the startpoint, endpoint, path group and delay type (max = setup, min = hold).
- Then read arrival, required and slack. Setup slack = required − arrival.
- Always label a report with its stage: pre-layout, placed, post-CTS or routed. 📘

### 5.3 Formality

✅ from `lec.tcl`: RTL vs synthesized netlist **and** RTL vs routed netlist. Both give `Verification SUCCEEDED`, 232/232 points (33 outputs + 199 flops).

```tcl
set_svf default.svf                          ;# DC's guidance (ungrouping, renaming, retiming)
read_db  <std .db>
read_sverilog -r <rtl files>  ; set_top r:/WORK/<top>     ;# -r = reference
read_verilog  -i <netlist>    ; set_top i:/WORK/<top>     ;# -i = implementation
match ; report_unmatched_points
verify                                        ;# 1 = SUCCEEDED
report_failing_points
```

- Run as `IMPL=synth|apr synopsys-run fm_shell -f lec.tcl`.
- ⚠ **`impl` is a reserved read-only variable in Formality** (`FM-414`). Don't name your own variables `impl` or `ref`.
- The routed netlist includes CTS buffers and resized cells, and Formality still proves equivalence. That's the point of checking after APR.

### 5.4 ICC2 Library Manager: building the NDM

ICC2 **only** reads **NDM** reference libraries.
SAED32 ships Milkyway (ICC1-era) data, plus a set of 2022 prebuilt NDMs that are **broken** (see §6).
The working recipe ✅ (`build_ndm.tcl`, run in `icc2_lm_shell`):

```tcl
set E23 /srv/auto/apps/saed32_edk/2023
create_workspace -technology $E23/tech/milkyway/saed32nm_1p9m_mw.tf saed32rvt_ws
read_lef -include cell $E23/lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef
read_db [glob $E23/lib/stdcell_rvt/db_nldm/saed32rvt_{ss0p95v125c,tt1p05v25c,ff1p16vn40c}.db]
check_workspace                                   ;# must print "Workspace check succeeded!"
commit_workspace -force -output ndm/saed32rvt.ndm ;# "... created 294 frames"
```

- **Tech file:** the stock Milkyway `.tf` loads fine in **Library Manager**. It only needs to be ICC2-parseable there.
- **Cell LEF:** you must use the one under `SAED32_EDK/lib/stdcell_rvt/lef/` (350 MACROs).
  - The obvious `lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef` is 14 KB of **tech only, zero MACROs**. That's why earlier attempts got `LEFR-012 no technology` / `LM-010 No libraries to commit`.
  - With the tech-only LEF, `read_db` then fails with `LM-035 Design AND2X1_RVT does not exist in physical libraries`.
- **Several corners** in one NDM: `read_db` several `.db` files. The NDM gets one timing "pane" per corner.
- **Workspace name ≠ library name**: `create_workspace saed32rvt` + a LEF library also called `saed32rvt` gives `LEFR-027`.
- **Expected warnings** (record them; they're library characteristics):
  - `TECH-025 VIA1 onGrid and onWireTrack coexist`
  - `LEFR-011` bus-bit characters
  - `LM-006` duplicate arcs
  - "Direction inout for port VDD/VSS"
  - `FRAM-066` very large M1 routing blockages
- **`group_libs`** only works in exploration mode (`LM-085`). The normal flow doesn't need it.
- **Macros (SRAM):** the same recipe with `lib/sram/lef/saed32sram.lef` + `lib/sram/db_nldm/saed32sram_*.db` gives `ndm/saed32sram.ndm` (35 frames) ✅. See §7 to use it.
- **Don't bother with `generate_frame_from_mw`.** It still fails with *"unable to find a valid Milkyway or IC Compiler executable"*, even with Milkyway Y-2026.03 on PATH. It wants legacy `icc_shell`, which CAE doesn't ship. LEF+db replaces it completely.

### 5.5 IC Compiler II: place & route

Each step below is from `apr.tcl` ✅, in order, with why it's there.

#### 5.5.1 Design library + parasitics

```tcl
create_lib $TOP.dlib -ref_libs [list $STD_NDM] -use_technology_lib $STD_NDM
read_parasitic_tech -tlup $TLUP/saed32nm_1p9m_Cmax.tluplus -layermap $TLUP/saed32nm_tf_itf_tluplus.map -name Cmax
read_parasitic_tech -tlup $TLUP/saed32nm_1p9m_Cmin.tluplus -layermap $TLUP/saed32nm_tf_itf_tluplus.map -name Cmin
read_verilog netlist/$TOP.v -top $TOP ; link_block ; connect_pg_net -automatic
```

- `-use_technology_lib` takes the tech from the NDM, so you don't need `-technology`. Give it the **path**; the library *name* gives `LIB-059`.
- TLU+ files are in `$EDK/tech/star_rcxt/`: Cmax, Cmin, nominal, plus the `.map`.

#### 5.5.2 MCMM: one mode, one corner, one scenario

```tcl
remove_modes -all; remove_corners -all; remove_scenarios -all
create_mode func ; create_corner ss0p95v125c
create_scenario -mode func -corner ss0p95v125c -name func_ss0p95v125c ; current_scenario func_ss0p95v125c
read_sdc netlist/$TOP.sdc
set_parasitic_parameters -corners ss0p95v125c -late_spec Cmax -early_spec Cmin
set_process_number -corners ss0p95v125c 0.99
set_voltage 0.95 -corners ss0p95v125c -object_list VDD ; set_voltage 0.00 -corners ss0p95v125c -object_list VSS
set_temperature   -corners ss0p95v125c 125
set_scenario_status func_ss0p95v125c -active true -setup true -hold true -leakage_power true -dynamic_power true
```

- The corner's P/V/T must match a pane in the NDM (from the `.lib` `operating_conditions`). Check with `report_pvt`.
- Don't use `set_process_label` with this NDM: its panes have no label, and setting one *creates* a mismatch.
- Adding a hold corner: `create_corner ff…`, a second scenario with `-setup false -hold true`, and `ff1p16vn40c` P/V/T (the NDM already has that pane).

#### 5.5.3 Routing layers

```tcl
set_attribute [get_layers {M1 M3 M5 M7 M9}]  routing_direction horizontal
set_attribute [get_layers {M2 M4 M6 M8 MRDL}] routing_direction vertical
set_ignored_layers -max_routing_layer M7
```

- The SAED32 `.tf` defines no preferred directions; ICC2 derives some and says so. 📘
- **MRDL** had none at all. With the first NDM (built from a patched techfile), global routing **segfaulted** right after `ZRT-025 Layer MRDL does not have a preferred direction`. Set it explicitly anyway.
- Pitches (from the `.tf`): M1/M2 0.152, M3/M4 0.304, M5/M6 0.608, M7/M8 1.216, M9 2.432 µm.

#### 5.5.4 Floorplan + pins

```tcl
initialize_floorplan -core_utilization 0.6 -core_offset 4.864   ;# 4.864 = 2 x M9 pitch: rows and tracks share an origin
place_pins -self
```

- Site `unit` is 0.152 × 1.672 µm, and SAED32 rows are 1.672 µm tall.
- For a fixed die: `-control_type die -boundary {{0 0} {W H}}` 📘.

#### 5.5.5 Power grid

```tcl
connect_pg_net -net VDD [get_pins -hierarchical */VDD] ; connect_pg_net -net VSS [get_pins -hierarchical */VSS]
create_pg_std_cell_conn_pattern rail -layers {M1} -rail_width 0.06          ;# = cell rail width in the LEF
set_pg_strategy rails -core -pattern {{name: rail} {nets: VDD VSS}} ; compile_pg -strategies rails
create_pg_mesh_pattern mesh -layers {{{vertical_layer: M6} {width: 0.4} {spacing: interleaving} {pitch: 10}} \
                                     {{horizontal_layer: M7} {width: 0.4} {spacing: interleaving} {pitch: 10}}}
set_pg_strategy meshs -core -pattern {{name: mesh} {nets: VDD VSS}} ; compile_pg -strategies meshs
```

- Don't `create_net -power VDD` after `connect_pg_net -automatic`; it already made them (`DES-150`).

#### 5.5.6 Implementation

```tcl
place_opt            ;# global place + optimization + legalization
clock_opt            ;# CTS + clock routing + post-CTS optimization (it also does global route)
route_auto           ;# global + track + detail route
route_opt            ;# post-route optimization with real parasitics
route_detail -incremental true -initial_drc_from_input true -max_number_iterations 30
create_stdcell_fillers -lib_cells [get_lib_cells */SHFILL*_RVT] ; connect_pg_net -automatic
remove_stdcell_fillers_with_violation
```

- To **re-route from scratch**, `remove_routes` + `route_auto` does *nothing* (`ZRT-607 Skipping global routing as it has already been run in … clock_opt`). You end up with 1,686 open nets and a fake "0 DRC".
  Use explicit `route_global; route_track; route_detail`. Always check `open nets = 0` next to the DRC count.
- Adam16 ✅ after `route_opt`:
  - Setup WNS +0.04 ns (ICC2), hold +0.06 ns, 0 violating endpoints
  - Clock: 199 sinks, 2 levels, 4 repeaters, latency 0.08 ns, skew 0.02 ns
  - Utilization about 0.51, wirelength about 28 mm, 0 open nets, 189 DRCs (§9)

#### 5.5.7 Reports and handoff

```tcl
check_routes ; report_qor -summary ; report_timing ; report_utilization ; report_clock_qor -type summary ; report_power
save_block ; save_lib
write_verilog -exclude {pg_objects physical_only_cells} $TOP.apr.v   ;# no fillers in the logical netlist
write_parasitics -output $TOP                                         ;# -> $TOP.Cmax_125.spef, $TOP.Cmin_125.spef
write_sdc -output $TOP.apr.sdc ; write_sdf $TOP.sdf
write_gds -hierarchy all -long_names -merge_files $EDK/lib/stdcell_rvt/gds/saed32nm_rvt_oa.gds $TOP.gds
```

- `report_area` is a **DC** command; ICC2 errors on it. Use `report_utilization` / `report_qor`.
- Without `-merge_files`, the GDS contains only cell frames, not real cell geometry.

#### 5.5.8 Looking at the layout

- **Interactive** (you, in Guacamole or MobaXterm): `synopsys-run icc2_shell`, then `open_lib cpu16_core.dlib; open_block cpu16_core; start_gui`. 📘
  - The title bar should read `cpu16_core.dlib:cpu16_core.design`.
  - The Property Editor shows `origin`, `orientation`, `physical_status`.
  - View → Error Browser shows the DRC markers.
  - Hiding a layer in View Settings doesn't delete anything.
- **Headless PNG** ✅: `run.sh <dir> shot` starts a private Xvfb and runs `gui_start`, `gui_zoom -full` and `gui_write_window_image`. It's for scripted portfolio images. It's never part of `all`, and the lab runbook asks automated agents not to launch GUIs.
- The earlier routed Adam16 image is `~/synopsys_debugging/results/cpu16_core_layout.png`.

### 5.6 PrimeTime: sign-off STA

✅ from `sta.tcl`:

```tcl
set link_path [concat * $STD_DB]
read_verilog $TOP.apr.v ; current_design $TOP ; link_design
read_parasitics -format spef $TOP.Cmax_125.spef
report_annotated_parasitics -check          ;# every real net must be "RC network"
read_sdc $TOP.apr.sdc ; set_propagated_clock [all_clocks]   ;# real clock tree after CTS
update_timing -full ; check_timing -verbose
report_timing -delay_type max -max_paths 10 ; report_timing -delay_type min -max_paths 10
report_constraint -all_violators ; report_clock_timing -type skew
write_sdf -version 3.0 $TOP.pt.sdf           ;# the SDF gate-level sim should use
```

- Adam16 ✅: **setup WNS +0.004 ns, hold WNS +0.060 ns**.
  - PrimeTime is slightly more pessimistic than ICC2 (+0.04). That's normal, and it's why sign-off STA exists.
  - 1622/1622 pin-to-pin nets annotated. There are 50 loadless nets (unused flop QN outputs) and 6 driverless nets.
  - `check_timing`: only "clk has no driving cell", which is benign.
- To tighten the clock, lower `CLK_PERIOD` in `config.tcl` and rerun. Setup margin at 3.0 ns is ~4 ps, so 3.0 ns is about Fmax for this corner.

### 5.7 Gate-level simulation with SDF

✅ from `sim.sh`. It uses the same tb for all three runs:

```bash
CELLS=/srv/auto/apps/saed32_edk/2023/lib/stdcell_rvt/verilog/saed32nm.v     # *_RVT names = match the netlist
vcs … +nospecify +notimingcheck $CELLS ../$TOP.apr.v <tb models> <tb> -o simv_gate            # zero-delay
vcs … +neg_tchk -sdf max:tb.dut:../$TOP.pt.sdf $CELLS ../$TOP.apr.v <tb models> <tb> -o simv_sdf   # routed delays
```

- **Use PrimeTime's SDF.** ICC2's `write_sdf` escapes top-level bus ports (`\mem_rdata[15]`), and VCS then drops those interconnect delays (`SDFCOM_PONF` ×10, `SDFCOM_UHICD` ×1). With `$TOP.pt.sdf`: **0 warnings**.
- Results ✅: RTL, gate and gate+SDF traces are **identical** over 2,000 cycles; 0 timing violations; the negative test is detected.
- The testbench clock is 10 ns. The SDF run is a *functional* check with real delays; at-speed timing is PrimeTime's job.

---

## 6. The SAED32 kit map

Root: `/srv/auto/apps/saed32_edk/2023` (EDK). `2022` is the same tree plus the broken NDMs.

| Need | Use this ✅ | Not this ⚠ |
|---|---|---|
| Timing `.db` | `lib/stdcell_rvt/db_nldm/saed32rvt_<corner>.db` (the handouts use the copy under `SAED32_EDK/lib/stdcell_rvt/db_nldm/`) 📘 | Private copies with renamed cells |
| Cell LEF | `lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef` (350 macros) | `lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef` (tech only, **0 macros**) |
| Tech file | `tech/milkyway/saed32nm_1p9m_mw.tf`, in **Library Manager** | Same file in `icc2_shell create_lib -technology` (`TECH-006` in the old session) |
| NDM | Build your own (§5.4) | `2022/lib/stdcell_*/ndm/*.ndm`: different cell release (1.824 µm rows, 0.32×2.88 site), every delay `??` in X-2025.06, `place_opt` → `OPT-041`. Their `ndm/tf/*.tf` has the same wrong site. |
| TLU+ | `tech/star_rcxt/saed32nm_1p9m_{Cmax,Cmin,nominal}.tluplus` + `saed32nm_tf_itf_tluplus.map` | — |
| Cell GDS | `lib/stdcell_rvt/gds/saed32nm_rvt_oa.gds` | — |
| Sim models | `lib/stdcell_rvt/verilog/saed32nm.v` (`*_RVT`) | `~/ECE551/SAED32_lib_RVT` (old, missing cells) |
| SRAM | `lib/sram/{lef/saed32sram.lef, db_nldm/…, gds/, verilog/}` | — |
| HVT/LVT | `lib/stdcell_{hvt,lvt}/lef/` have macros; `db_nldm` has `saed32{hvt,lvt}_<corner>.db` | — |
| Milkyway | Not needed | `generate_frame_from_mw` (fails, needs `icc_shell`) |

- Library consistency check that exposed the bad NDM: Liberty `INVX1_RVT` area 1.27072 = LEF `SIZE 0.76 BY 1.672`, and the NDM had 0.99 × 1.824.
- **Always cross-check area vs. geometry** when you adopt a library.

---

## 7. Adapting the flow to your own RTL

1. **Copy the kit** for each project: `cp -r saed32_icc2_kit ~/myproj/flow`. Keep `ndm/`; it's design-independent. Or point `STD_NDM` at the shared one.
2. **Edit `config.tcl`:**
   - `TOP`, `RTL_DIR`, and `RTL_FILES` in **dependency order** (packages first).
   - `CLK_PORT`, `CLK_PERIOD`.
   - `IO_DELAY`: a real budget agreed with whatever drives and consumes your ports.
   - `CORE_UTIL`: 0.5–0.7. Lower it if routing congests.
   - `MAX_LAYER`: keep the top layers for the power mesh.
3. **Anything `synth.tcl` doesn't model yet:**
   - **Several clocks / generated clocks:** add `create_clock` / `create_generated_clock` and `set_clock_groups` to `synth.tcl`. They flow through the SDC to ICC2 and PT automatically.
   - **Asynchronous reset:** fine as is. Consider `set_false_path -from [get_ports rst_n]`, or model a reset synchronizer.
   - **Macros (SRAM):** uncomment `EXTRA_DBS` / `EXTRA_NDMS` in `config.tcl`. Instantiate the SRAM cell (e.g. `SRAM1RW64x8`) in RTL. Before `place_opt`, place the macro in the floorplan (`set_cell_location` / `create_placement -floorplan`) and add a keepout (`create_keepout_margin`). Verilog models are in `lib/sram/verilog/`.
     - The SRAM NDM builds ✅, but **it hasn't yet been run through placement**. Expect some work here.
   - **Design too big for the default floorplan:** lower `CORE_UTIL`, or use a fixed `-boundary`.
4. **Testbench:** replace `tb/cpu16_smoke_tb.sv` (or set `TB=` / `TB_EXTRA=` env vars for `sim.sh`). Keep the 5 principles in §5.1.
5. **Run `./run.sh <newdir>`** and use the table in §3 as your checklist.

---

## 8. Troubleshooting encyclopedia

Every entry below was hit on CAE with this exact tool set.

| Message | Where | Meaning → fix |
|---|---|---|
| `WARNING: <tool> was invoked without loading the appropriate modules first!` | host | You hit the stub in `/usr/local/cae/bin`. Run `module load synopsys/suite` → `synopsys-run`. |
| `FATAL: "<tool>": executable file not found in $PATH` | synopsys-run | The module isn't loaded in *this* shell (pipe or subshell, or `set -u`). See §2.3. |
| `TECH-006 syntax error … line 405` / `LIB-007 Cannot load technology file` | icc2_shell `create_lib -technology <mw.tf>` | Old path. Build the NDM in Library Manager and use `-use_technology_lib`. |
| `unknown option '-tech_lef'` / `unknown command 'read_lef'` | icc2_shell | Those belong in `icc2_lm_shell` (`read_lef`), not `icc2_shell`. |
| `DES-001 Current block is not defined` (read_tech_lef) | icc2_shell | Needs an open block. Not the way to build a ref lib anyway. |
| `NDM-164` / `NDM-020 not a valid NDM binary` / `LIB-027 not a valid library` | `create_lib -ref_libs <lef or mw dir>` | `-ref_libs` wants a **built NDM**. It doesn't auto-convert LEF/Milkyway here. |
| `LIB-117 … technology file not specified` → `FILE-001 …/lib.ndm` | same | Same cause. Build the NDM first. |
| `LIB-059 technology library '<name>' does not match …` | `create_lib -use_technology_lib` | Pass the NDM **path**, not its name. |
| `LEFR-027 library name cannot be same as workspace name` | lm_shell | Rename the workspace (`<name>_ws`). |
| `LEFR-012 The library has no technology information` / `LM-010 No libraries to commit` | lm_shell | You read the tech-only LEF. Use the `SAED32_EDK/…/lef` one and `create_workspace -technology <tf>`. |
| `LM-035 Design AND2X1_RVT does not exist in physical libraries` | lm_shell `check_workspace` | The `.db` has cells the LEF lacks, i.e. the tech-only LEF again. |
| `LEFR-065 height or width of MACRO … not a multiple of any site` | lm_shell | The tech file's site doesn't match the cells. You used `2022/…/ndm/tf/*.tf` (0.32×2.88). Use the stock `.tf`. |
| `LM-085 Current workspace is not in exploration mode` | lm_shell `group_libs` | Drop `group_libs`. |
| `Cannot export Milkyway FRAM as unable to find a valid Milkyway or IC Compiler executable` | lm_shell `generate_frame_from_mw` | Needs legacy `icc_shell`. Not fixable on CAE; use LEF+db. |
| `Bus error encountered` at lm_shell startup | lm_shell (old session) | Not reproduced since the container migration. If it happens, rerun and save the stack trace. |
| delays `??` in `report_delay_calculation`, `report_timing` "No paths" | icc2_shell | The ref lib's timing is unusable. That's the 2022 prebuilt NDMs; rebuild. |
| `Error: Cannot find buffer or inverter with valid delay for all corners` / `OPT-041` | place_opt | Same root cause, or a corner P/V/T with no matching NDM pane (`report_pvt`). |
| `PVT-030 … N process label mismatches` / `PVT-023` | place_opt | `set_process_label` must match the pane labels exactly, or be omitted when the panes have none. |
| `DES-150 Net 'VDD' already exists` | icc2_shell | `connect_pg_net -automatic` already created it. Remove your `create_net`. |
| `Segmentation fault … (Bad read from 0x0)` right after `ZRT-025 Layer MRDL does not have a preferred direction` | route (global) | Set `routing_direction` on MRDL (and all layers). Also seen with a hand-patched tf; the stock tf plus directions works. |
| `ZRT-607 Skipping global routing as it has already been run in … clock_opt` | route_auto after remove_routes | Run `route_global` / `route_track` / `route_detail` explicitly. |
| "TOTAL VIOLATIONS = 0" but `open nets = 1686` | check_routes | Nothing was routed (see above). Always read both numbers. |
| `Error: disabled command report_area encountered` | icc2_shell | DC-only command. Use `report_utilization`. |
| `Error: Invalid value '{VIA1 10…` | set_app_options | That option takes a Tcl list of pairs. Check `report_app_options <name>` for the type. |
| `Cannot initialize GUI. The connection to X-server ':N' is broken or refused` | gui_start | No reachable X server. Use a real `$DISPLAY` (Guacamole/MobaXterm) or host Xvfb (§2.3). `xvfb-run` *inside* the container doesn't work. |
| `FM-414 Variable 'impl' is read-only` | fm_shell | Reserved name. Rename your variable. |
| `CMD-015 could not open output redirect file` | any | The path is bad, often a variable that expanded to something with `:` or `/`. |
| `Warning-[SDFCOM_PONF] Port not found … \mem_rdata[15]` | vcs -sdf | ICC2's SDF escapes bus ports. Use PrimeTime's `write_sdf`. |
| Test "passes" but only touches 2 addresses | your tb | Vacuous test (wrong memory model / stimulus). Check activity (§5.1). |

**General method** 📘✅:
- Read the **first** error.
- Classify every warning as a *library limitation*, a *missing flow input*, or a *real design problem*.
- Never suppress one to make a log look clean.
- `help -verbose <cmd>`, `man <cmd>` and `report_app_options <pattern>` all work in every Synopsys shell.
- Every run goes in a fresh directory, with logs next to their outputs.

---

## 9. Known limitations and open items

1. **189 route DRCs** on Adam16: ~100 VIA1 off-grid, ~27–60 M1 different-net spacing, ~35–55 M1/M2 needs-fat-contact, ~5 M2 minimum area.
   - All are at signal pins on M1/VIA1/M2. There are **0 open nets**, and timing, LEC and SDF simulation all pass.
   - Root cause, from probing a violation: `VIA23` lands exactly on-track (38.608 = 254 × 0.152 µm), but the `VIA12` under it is pushed 0.025 µm to hit the M1 pin of a mirrored `OR2X4_RVT`.
   - SAED32's M1 pin shapes don't sit on the 0.152 µm track grid, while the Milkyway techfile demands `onWireTrack = 1` / `onGrid = 1` for VIA1 and fat-contact rules the ICC1-era tf expresses in ways ICC2 partly ignores (`ZRT-007 Ignore fat rule`).
   - **These didn't help** (each within ±10 violations):
     - `route.common.via_on_grid_by_layer_name` true or false
     - `wire_on_grid_by_layer_name`
     - `route.detail.generate_extra_off_grid_pin_tracks`
     - full reroutes
     - a track-aligned core offset
   - Classification: **teaching-library/techfile limitation**. The ICC2-native SAED32 techfile likely lives in the permission-denied `saed32_pdk`.
   - Fine for a portfolio image. Not a tape-out-clean claim. **Next step: ask CAE or your professor for read access to `saed32_pdk`.**
2. **FSM coverage 46%** in the smoke test. By design, it doesn't exercise control flow. Adam's own tests (`tb/`) should cover branches, jumps and traps. Run them with `sim.sh` via `TB=`.
3. **6 driverless nets** in PrimeTime's annotation report. They're probably tie-offs or unused ports. They don't affect timing, but it's worth checking `report_net` on them once.
4. **SRAM NDM** is built but untested in a placed design.
5. **Not done here (blocked for the agent, not for you):**
   - The companion lab `~/cae-synopsys-guides/lab/run_lab.py` (cloned). Automated execution of that externally sourced code was blocked by the session's safety classifier.
   - Simulating Adam's existing testbenches in `~/RTL_sandbox/16_Bit_CPU/tb/`.
   - Commands to run it yourself are in §10.

---

## 10. Appendix

### 10.1 Handout lab (`sb_flop`), expected results 📘

```bash
module load synopsys/suite ; synopsys-run
cd ~/cae-synopsys-guides/lab
python3 run_lab.py simulation     # expect LAB_RESULT=PASS; SB_SNPS_SIM_PASS; negative "data failed" at 21000 ps
python3 run_lab.py synthesis      # expect 2 cells (q_reg=DFFSSRX1_RVT + tie-low), area 7.116032, slack 8.86 ns
```

- Coverage (DUT `tb.dut`): line 100%, branch 100%, toggle 87.5%. The missing bin is rst 0→1, because reset is never reasserted.
- Physical: `icc2_lm_shell -f physical/build_reference.tcl` (294 frames), then `icc2_shell -f physical/floorplan.tcl` (`q_reg` ≈ `{8.0387 8.7512}`, R0, placed).
- The handout's lab uses the **TT 1.05 V 25 °C** teaching corner. This kit signs off at **SS 0.95 V 125 °C**, so numbers aren't comparable across the two.
- The runbook's "beyond the handout" §7 items all have verified answers above:
  - routing directions: §5.5.3
  - TLU+: §5.5.1
  - scenario: §5.5.2
  - PG, place, CTS, route: §5.5.5–5.5.6

### 10.2 Command cheat sheet

| Want | Command |
|---|---|
| What does this module set? | `module show synopsys/iccompiler2/2026.03` or `cat /srv/auto/modules/modulefiles/…lua` |
| Tool help | `help -verbose <cmd>` · `man <cmd>` · `report_app_options <glob>` · `<cmd> -help` |
| Save any report | `redirect -file x.rpt {report_timing -max_paths 5}` or `report_… > x.rpt` |
| ICC2 object attrs | `get_attribute [get_cells U123] {origin orientation physical_status ref_name}` |
| DRC list | `open_drc_error_data zroute.err; get_drc_errors -error_data zroute.err` |
| Which corner/pane is used | `report_pvt` |
| What's in an NDM | `report_lib -timing <lib>` · `report_ref_libs` |
| Reopen a design | `open_lib X.dlib; open_block TOP` |

### 10.3 Links

- CAE software guide (modules / containers): <https://kb.wisc.edu/cae/163133> · <https://kb.wisc.edu/cae-software-guide>
- Guacamole sign-in: <https://kb.wisc.edu/cae/163323>
- Companion lab repo (Abhinav Nandwani): <https://github.com/abhinavnandwani/cae-synopsys-guides>
- ICC2 product page: <https://www.synopsys.com/implementation-and-signoff/physical-implementation/ic-compiler.html>
- Verdi: <https://www.synopsys.com/verification/debug/verdi.html>
