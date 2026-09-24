# ICC2 / SAED32 Workflow — Handoff Brief for Agent Claude on CAE Linux Machines

## PURPOSE OF THIS FILE
Adam (CompE student, UW-Madison) has a working RTL→synthesis→FPGA→post-synth-sim
flow for a 16-bit CPU. He is blocked at ONE stage: building an ICC2-usable
reference library so he can place-and-route (APR) the CPU and produce a layout
image for his portfolio. This file hands off the complete state to an agent
instance running ON the CAE machines. The agent's job: **vet the machines
exhaustively for anything that unblocks the ICC2 library setup** — a prebuilt
NDM library, a newer NDM-native PDK, or the Milkyway/ICC1 tools needed to convert
the existing kit. CAE recently migrated/uprooted their whole system, so previously
absent things may now exist (possibly behind environment modules).

---

## THE ONE-SENTENCE BLOCKER
ICC2 (`icc2_shell`) needs reference libraries in **NDM** format; the installed
SAED32 kit ships physical libraries only in **Milkyway + LEF** format with **no
prebuilt NDM**; and the ICC2 Library Manager's Milkyway→frame converter
(`generate_frame_from_mw`) **fails because ICC1/Milkyway executables are not
installed** ("unable to find a valid Milkyway or IC Compiler executable"). So
there is currently no working path from the installed kit to an ICC2 reference library.

---

## ENVIRONMENT — CONFIRMED FACTS (verified by commands during the session)

### Tools present
- `icc2_shell` — version **X-2025.06** (May 2025 build). The ICC2 place-and-route tool.
- `icc2_lm_shell` — the ICC2 **Library Manager** (builds/manages NDM reference libraries).
- `icc2_lm_shell` was found at `/opt/cae/bin/icc2_lm_shell`; `icc2_shell` at `/opt/cae/bin/icc2_shell`.
- `lc_shell` — Library Compiler (present in /opt/cae/bin).
- `Milkyway` — a `Milkyway` entry appeared in `/opt/cae/bin` grep, BUT the FRAM
  conversion still failed to find a valid Milkyway/ICC executable, so its presence
  is ambiguous / possibly non-functional. **VET THIS.**
- `calibre`, `calibre-standalone` — Siemens physical verification (present).
- Design Compiler (`dc_shell`) — WORKS. Synthesis is fully functional (see below).
- Questa/`vsim` — WORKS (used for post-synth sim).

### Tools ABSENT (confirmed)
- `icc_shell` (ICC1 place-and-route) — **NOT installed**. `which icc_shell` returns
  nothing; not in `/opt/cae/bin/`. This is the root of the mismatch: the kit and the
  ECE551 tutorial are ICC1/Milkyway-based, but only ICC2 exists.

### The PDK / kit
- Path: `/cae/apps/data/saed32_edk-2023` (Synopsys SAED 32/28nm educational kit).
- Standard cells used for synthesis: **RVT**, slow corner:
  `/cae/apps/data/saed32_edk-2023/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db`
  (naming: saed32 = 32nm, rvt = regular-Vt, ss = slow-slow, 0p95v = 0.95V, 125c = 125°C)
- **No `.ndm` files exist anywhere in the SAED32 kit** (`find ... -name "*.ndm"` empty).
- Physical data available in the kit:
  - **LEF** (contains tech + cell macros):
    `/cae/apps/data/saed32_edk-2023/lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef`
    (verified it has both a tech section — LAYER M3/VIA3/M4 etc. — and cell MACROs)
  - **Milkyway library** (valid, has CEL/FRAM):
    `/cae/apps/data/saed32_edk-2023/lib/stdcell_rvt/milkyway/saed32nm_rvt_1p9m/`
    (confirmed CEL/, FRAM/, lib, .lock present at this level; also nested again at
    `.../saed32nm_rvt_1p9m/saed32nm_rvt_1p9m/` which also has CEL/FRAM)
  - **Milkyway techfiles** (multiple versions):
    `/cae/apps/data/saed32_edk-2023/tech/milkyway/saed32nm_1p9m_mw.tf`
    plus `.v8` `.v9` `.v10` `.v11` `.v12` variants, and `saed32nm_1p9m_oa.tf`
  - **OpenAccess (OA) libraries** exist:
    `/cae/apps/data/saed32_edk-2023/lib/oa/saed32nm_stdcell_rvt_oa/`
    with `dbTechDataBackupOriginal.tf` — **NOT yet fully vetted as an ICC2 source.**
  - **TLU+ parasitic models** (confirmed, for RC extraction):
    `/cae/apps/data/saed32_edk-2023/references/orca/icc/ref/tlup/saed32nm_1p9m_Cmax.tluplus`
    `.../saed32nm_1p9m_Cmin.tluplus`
    `.../saed32nm_tf_itf_tluplus.map`
- The kit's reference ICC flow is ICC1/Milkyway:
  `/cae/apps/data/saed32_edk-2023/references/orca/icc/scripts/` contains
  `setup.tcl`, `read.tcl`, `floorplan.tcl`, `place.tcl` — these use `create_mw_lib`
  and `import_designs` (ICC1 commands that DO NOT EXIST in ICC2).
- Prebuilt Milkyway reference libs exist at
  `/cae/apps/data/saed32_edk-2023/references/orca/icc/ref/ref/`
  → `PLL2/  saed32_io_fr/  saed32nm_svt_1p9m/` (note: that std-cell one is **SVT**, not RVT).

### Machine details
- Hosts seen: `best-tux.cae.wisc.edu`, and login nodes like `tux-122`, `linux-2619`, `linux-2621`.
- User home: `/userspace/ashebani` (NOT `/home/ashebani` — this tripped up a path early).
- Adam's ECE551 dir: `~/ECE551/` contains: `551_Project-main/ designvision/ ex17/
  ICCtut/ modelsim/ random/ SAED32_lib/ SAED32_lib_RVT/`
  - `~/ECE551/ICCtut/` was created BY ADAM following a **2018** ICC tutorial video;
    it only contains `icc2_command.log` (shows a trivial gui pref set + quit — no
    working build) and `icc2_output.txt`. The tutorial is for ICC1 and the license
    it referenced is expired. **Not a working recipe.**
  - `~/ECE551/SAED32_lib_RVT/` — a precompiled **Questa simulation** library
    (contains `_info`, `_lib1_0.qdb`, etc.). This is for gate-level SIM, NOT for ICC2.
    It did NOT contain the cells the netlist needed (see sim section) — the sim was
    ultimately fixed a different way.

---

## WHAT ADAM HAS DONE (working / complete)

### 1. RTL — Adam16 CPU (COMPLETE)
- 16-bit, LC-3-inspired, multi-cycle FSM-controlled CPU in SystemVerilog.
- Top module: `cpu16_core`. Submodules include `cpu16_control_fsm` (u_ctrl),
  a datapath (u_dp), regfile (rf), ALU, and an ISA package `cpu16_isa.sv`.
- External SRAM model `SramSBC` lives in `rtl/Sram.sv` (module name ≠ filename).
- Repo layout under `~/RTL_sandbox/16_Bit_CPU/`:
  `rtl/ scripts/ tb/ sim/ synth/ apr/ README.md`

### 2. DC Synthesis (COMPLETE, WORKS)
- Script `scripts/adam16.dc` (or in `synth/`). Runs in `dc_shell`.
- Library setup that WORKS:
  - `set LIBNAME saed32rvt_ss0p95v125c`
  - `set target_library "$LIBDIR/$LIBNAME.db"`, `set link_library "* $target_library"`
  - cells confirmed via `get_lib_cells` → plain names: INVX1, INVX2, AO22X1, DFFX1, etc.
    (NOTE: the `.db` uses PLAIN cell names, NO `_RVT` suffix — this matters, see sim.)
- Outputs written to `synth/work/netlist/`:
  - `cpu16_core.mapped.v`  (gate netlist — **the ICC2 input**)
  - `cpu16_core.mapped.sdc` (constraints — **the ICC2 input**)
  - `cpu16_core.ddc`
- Clock constrained (~3 ns target in the script; tune for Fmax).
- Real QoR/area/timing reports were produced.

### 3. FPGA flow (COMPLETE) — separate, on a Basys 3
- Vivado, Artix-7 `xc7a35tcpg236-1`. Bitstream built and programmed to real hardware.
- (An early failure was caused by the project being set to the wrong part — AC701
  instead of the Basys 3 `xc7a35tcpg236-1`; fixed by selecting the correct Parts entry.)
- Vivado can also produce portfolio visuals (device view colored by module, schematic)
  — this is the FPGA-side fallback for a "chip visual" while ICC2 is blocked.

### 4. Post-synth gate-level simulation (COMPLETE, PASSES 3/3)
- This was a long debug. Final working approach, in `sim/work/`, via Questa `vsim`:
  - The precompiled `~/ECE551/SAED32_lib_RVT` did NOT have the needed cells → abandoned.
  - FIX: compile the RVT cell models FROM SOURCE into the `work` library. Source file:
    `/cae/apps/data/saed32_edk-2023/lib/stdcell_rvt/verilog/saed32nm.v`
  - **CRITICAL GOTCHA:** that `.v` names cells WITH `_RVT` suffix (DFFX1_RVT), but the
    synth netlist instantiates PLAIN names (DFFX1). Fixed by stripping the suffix:
    `sed 's/_RVT//g' saed32nm.v > saed32nm_plain.v` then compiling the plain version.
  - Compile order: cell models → netlist → SRAM (`rtl/Sram.sv`) → TB.
  - Load: `vsim -c +notimingchecks -voptargs=+acc work.tb_cpu16_gate -do "run -all; quit"`
  - The RTL testbench probed internal hierarchy (`dut.u_dp.rf.r[]`, `dut.u_ctrl.state`)
    which synthesis FLATTENS away → made a black-box gate TB (`tb/tb_cpu16_gate.sv`)
    that checks MEMORY only (external SRAM `imem.mem[]`), plus halt via the surviving
    flat signal `dut.\u_ctrl/state ` (escaped name). 3 memory-observable tests pass.
- Takeaway for the agent: sim is DONE; don't redo it. Only relevant if the agent needs
  cell-name conventions (plain vs _RVT) or the flatten behavior as reference.

---

## WHAT ADAM HAS NOT DONE / IS BLOCKED ON

### THE BLOCKER: build an NDM reference library for ICC2
Every attempted path failed. Exhaustive list of what was tried and the exact errors:

1. `create_lib $REFLIB -technology <milkyway.tf>` (in icc2_shell)
   → `TECH-006 syntax error` at line 405 of the .tf, then `LIB-007 cannot load
   technology file`. **Milkyway .tf is not parseable by icc2_shell's create_lib.**

2. `create_lib $REFLIB -technology <cell.lef>` (LEF as tech)
   → `LIB-007 Cannot load technology file`. **create_lib -technology won't take a LEF.**

3. `create_lib $REFLIB -tech_lef <cell.lef>`
   → `unknown option '-tech_lef'`. **That flag does not exist in X-2025.06.**
   (`help -verbose create_lib` options are: -technology, -use_technology_lib,
   -use_parasitic_tech_lib, -ref_libs, -convert_sites, -scale_factor, -base_lib,
   -dont_set_current.)

4. `create_lib $REFLIB` (bare) then `read_lef -library $REFLIB <cell.lef>`
   → `unknown command 'read_lef'`. **read_lef DOES NOT EXIST in icc2_shell.**
   (It exists in icc2_LM_shell instead — see below.)

5. `read_tech_lef <cell.lef>` (in icc2_shell, after bare create_lib)
   → `DES-001 Current block is not defined`. read_tech_lef exists in icc2_shell but
   wants a block/design context; not the right tool for building a fresh ref lib.

6. `set_current_lib` → `unknown command`. (Does not exist; current_lib is the getter.)

7. `create_lib $DLIB -ref_libs <cell.lef>` (let -ref_libs auto-build from LEF; the
   man page SAYS -ref_libs accepts "LEF files, and Milkyway libraries" and auto-builds)
   → `NDM-164 invalid argument` / `NDM-020 not a valid NDM binary file` /
   `LIB-027 not a valid library`. **-ref_libs treated the LEF as a prebuilt NDM binary
   instead of source to convert. Auto-build did NOT trigger.**

8. `create_lib $DLIB -ref_libs <milkyway_lib_dir>`
   → `LIB-117 Library configuration will not be performed: technology file not
   specified`, then it looked for `<mwdir>/lib.ndm` (`FILE-001 no such file`) →
   `LIB-027 not a valid library`. **Without -technology it skips conversion and
   assumes the ref is a prebuilt NDM.**

9. `create_lib $DLIB -technology <milkyway.tf> -ref_libs <milkyway_lib_dir>`
   → LIB-117 warning GONE (so -technology registered), but STILL looked for
   `lib.ndm` in the milkyway dir → FILE-001 / LIB-027. **create_lib will not
   auto-convert the Milkyway lib; it wants an already-built NDM.**
   (`lib.configuration.local_output_dir` man page says Milkyway physical source gets
   converted to frame libs under an `auto_frame_libs` subdir of that output dir — so
   the intended auto-convert MECHANISM exists, but did not fire here. Setting
   `set_app_options -name lib.configuration.local_output_dir -value ./built_libs`
   was added but did not change the lib.ndm-lookup behavior. WORTH RE-VETTING with
   more app-option tuning — see lib.configuration.default_flow_setup, which the man
   page says can point to a Tcl script with custom cell-library-creation settings.)

10. **In `icc2_lm_shell`** (the Library Manager — where read_lef DOES exist):
    - `create_workspace saed32rvt` (bare) then
      `read_lef -include {cell tech} <cell.lef>`
      → first errored `LEFR-027 library name cannot be same as workspace name`
        when `-library saed32rvt` matched the workspace name; fixed by dropping -library.
      → then `LEFR-012 The library has no technology information` on the tech read,
        and `commit_workspace` → `LM-010 No libraries to commit`. **read_lef -include
        tech did not establish usable technology from this LEF.**
    - Splitting into `read_lef -include tech` then `read_lef -include cell` — same
      LEFR-012 (no technology info). **NOT fully re-vetted with every -include /
      create_workspace -technology permutation — a candidate for the agent.**
    - `create_workspace -technology <milkyway.tf>` was NOT exhaustively tried in
      lm_shell (only in icc2_shell, where it TECH-006'd). **VET: does lm_shell's
      create_workspace -technology accept the Milkyway .tf, or a versioned .v12 .tf,
      where icc2_shell did not?**
    - **`generate_frame_from_mw -mw_lib <milkyway_lib> -output_directory ./frame_libs
      -overwrite saed32rvt_frame`**
      → **`Cannot export Milkyway FRAM as unable to find a valid Milkyway or IC
      Compiler executable.`** THIS IS THE HARD WALL. The dedicated Milkyway→frame
      converter needs a Milkyway or ICC1 executable to read the FRAM, and it cannot
      find one. (`generate_frame_from_mw` signature: -mw_lib, -log_file_dir,
      -output_directory, -overwrite, library_name.)

### Not done (downstream of the blocker — all trivial once the NDM exists):
- `read_verilog cpu16_core.mapped.v` + `link_block` + `read_sdc` (scripts staged).
- Floorplan (`initialize_floorplan`), placement (`place_opt`), CTS (`clock_opt`),
  routing (`route_auto`), timing reports, and the GUI layout SCREENSHOT (the actual
  portfolio deliverable). Conceptually understood; just needs a loaded design.
- TLU+ binding (`read_parasitic_tech`) — paths confirmed, staged in the setup script.

### GUI note
- ICC2 has a GUI (`start_gui` / `gui_start`), but needs `$DISPLAY` (X forwarding).
- Adam now uses **MobaXterm** (has a built-in X server) so GUIs display fine when
  connecting through it. `echo $DISPLAY` should be non-empty in a MobaXterm session.

---

## STAGED FILES (already written, ready to use once NDM exists)
Under `~/RTL_sandbox/16_Bit_CPU/apr/work/` (Adam runs ICC2 from here):
- `icc2_setup.tcl` — creates design lib (`-ref_libs` a built lib), reads TLU+, reads
  netlist+SDC, links. Currently fails at create_lib (the blocker). Once a valid NDM
  exists, change the `-ref_libs` to point at it and this should run through link.
- `build_ndm.tcl` — the lm_shell attempt (generate_frame_from_mw). Blocked on missing
  Milkyway executable.
All input PATHS in these are confirmed correct (LEF, .db, Milkyway lib, TLU+, netlist, sdc).

---

## AGENT: WHAT TO VET ON THE MACHINES (priority order)

CAE recently migrated their whole system. Previously-absent things may now exist,
possibly behind environment modules that are invisible to `which`/`find` until loaded.

### Priority 1 — Is there an NDM-native library ANYWHERE? (cleanest unblock)
```
find /cae/apps/data -name "*.ndm" 2>/dev/null
find /cae/apps -name "*.ndm" 2>/dev/null
find /cae -maxdepth 6 -name "*.ndm" 2>/dev/null
```
If ANY real standard-cell NDM exists (SAED32 or another kit), that's the path:
point `create_lib -ref_libs <it>` and skip conversion entirely. If it's a DIFFERENT
kit's cells, Adam must RE-SYNTHESIZE Adam16 against that kit's `.db` first (DC flow
works, easy), then P&R against its NDM.

### Priority 2 — Environment modules (migration systems often use these)
```
module avail 2>&1
module spider 2>&1 | head -100   # if Lmod
```
Look for: ICC1 / Milkyway / a Synopsys "milkyway" or "icc" module, a newer PDK module,
or an NDM-native kit. If the Milkyway tools are module-gated, `module load <x>` may make
`generate_frame_from_mw` find its executable — the entire blocker could vanish.
This is the SINGLE MOST LIKELY quick fix and was NOT checked before the session ended.

### Priority 3 — Is the Milkyway / ICC1 executable actually anywhere?
```
find /opt/cae -iname "*milkyway*" 2>/dev/null
find /opt/cae -iname "icc_shell" 2>/dev/null
find / -iname "icc_shell" 2>/dev/null | head
ls -la /opt/cae/bin/Milkyway    # a 'Milkyway' entry was seen here — is it real/runnable?
file /opt/cae/bin/Milkyway
/opt/cae/bin/Milkyway -help 2>&1 | head    # does it even run?
```
If a functional Milkyway/ICC1 binary exists (or can be put on PATH), then
`generate_frame_from_mw` in icc2_lm_shell should work → build the frame lib →
create_lib -ref_libs it → done.

### Priority 4 — Newer / other PDKs installed
```
ls -la /cae/apps/data/
find /cae/apps/data -maxdepth 2 -type d \( -iname "*saed*" -o -iname "*edk*" -o -iname "*pdk*" -o -iname "*nangate*" -o -iname "*freepdk*" -o -iname "*gpdk*" \) 2>/dev/null
```
A newer kit (e.g. SAED14, Nangate45, a foundry kit) may ship NDM natively and be
ICC2-ready out of the box. Same re-synth caveat as Priority 1.

### Priority 5 — Re-vet the icc2_lm_shell NDM build with untried permutations
The lm_shell path was not exhausted. Try, IN icc2_lm_shell:
- `create_workspace -technology <milkyway.tf> saed32rvt` (does LM accept the .tf where
  icc2_shell didn't? try plain AND the `.v12` versioned tf under tech/milkyway/)
- if a workspace with real tech is established, then `read_lef -include cell <cell.lef>`
  for macros, then `check_workspace`, then `commit_workspace -output ./saed32rvt.ndm`
- also inspect: `man create_workspace`, `man read_lef`, `man read_db`,
  `help -verbose *frame*`, `help -verbose *milkyway*`, `help -verbose *mw*` in lm_shell
- check the OA route: can lm_shell read the OpenAccess lib at
  `/cae/apps/data/saed32_edk-2023/lib/oa/saed32nm_stdcell_rvt_oa/` directly?
  (`help -verbose *oa*` / `read_oa` / OA-related commands)

### Priority 6 — Synopsys install root + shipped docs + any reference ICC2 flow
```
echo $SNPS_ROOT
ls /opt/cae/
find /opt -maxdepth 4 -iname "*icc2*" -type d 2>/dev/null
# a 2023 kit may ship an ICC2 (not just ICC1) reference flow somewhere:
find /cae/apps/data/saed32_edk-2023 -type d -iname "*icc2*" 2>/dev/null
find /cae/apps/data/saed32_edk-2023 -name "*.tcl" 2>/dev/null | xargs grep -l "create_lib\|read_ndm\|create_workspace" 2>/dev/null
```
If the kit has an ICC2 reference script or a prebuilt NDM tucked away, it has the exact
working recipe with correct paths — best possible find.

---

## DECISION TREE FOR THE AGENT
1. Found a usable standard-cell NDM (Priority 1/4)?  → point create_lib -ref_libs at it;
   re-synth first if it's a different kit's cells. Then run the staged flow. **DONE.**
2. Found a module that loads Milkyway/ICC1 or an NDM kit (Priority 2/3)? → load it;
   retry `generate_frame_from_mw` (build frame→NDM) OR use the NDM directly. **DONE.**
3. lm_shell permutation builds a valid NDM (Priority 5)? → use it. **DONE.**
4. Nothing works → produce a crisp findings report: exactly what tools/kits/modules/NDM
   exist, confirming the machines lack an ICC2-ready path, so Adam's CAE help-desk
   ticket / professor (Julie) email has authoritative evidence. Include the full
   inventory (ls /opt/cae/bin, ls /cae/apps/data, module avail, any .ndm found).

## HARD CONSTRAINTS / DON'T-REDO
- DC synthesis, FPGA bitstream, and post-synth sim are DONE. Do not redo them.
- Do NOT publish/commit licensed kit files (`.db`, `.lib`, `.lef`, `.ndm`, mapped
  netlist, GDS) to any public repo — SAED32 is licensed educational IP. Reports,
  metrics, scripts, and screenshots are fine to keep/share.
- Cell name convention: synth `.db` uses PLAIN names (DFFX1); the `.v` sim models use
  `_RVT` suffix. Relevant if any cell-name matching comes up.
- User home is `/userspace/ashebani`, not `/home/ashebani`.
- Run ICC2 from `~/RTL_sandbox/16_Bit_CPU/apr/work/`. Netlist+SDC are in
  `~/RTL_sandbox/16_Bit_CPU/synth/work/netlist/`.

## THE GOAL
Get a valid ICC2 reference library so `icc2_shell` can read `cpu16_core.mapped.v`,
link it, floorplan → place → CTS → route, and open the GUI for a layout screenshot.
That layout image is the portfolio deliverable Adam wants. Everything upstream is done.
