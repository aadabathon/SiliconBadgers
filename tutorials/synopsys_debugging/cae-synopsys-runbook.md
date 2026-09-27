# CAE Synopsys Flow Runbook (agent-facing)

Source: Abhinav Nandwani's CAE lab notes (RTL, Verification, Synthesis & Physical Design handouts, 23 Sep 2026), plus known issues from prior attempts on CAE.

**Goal:** reproduce the verified one-register flow end to end on CAE (sim → coverage → synth → ICC2 reference library → floorplan). Then scout what's needed to push ICC2 past initial placement (routing directions, TLU+, scenarios, PG, CTS, route). Report findings. Don't guess.

---

## 0. Ground rules

- **Every run goes in a fresh directory** under `~/cae-synopsys-guides/lab/runs/`. Never reuse or overwrite an old run dir. Always `cd` to the exact `RUN_DIRECTORY` the runner prints.
- **Log everything:** `cmd > something.log 2>&1`. Keep logs next to their outputs.
- **Exit codes are not verdicts.** On this install VCS returned exit 0 even on `$fatal`. Pass/fail = positive pass marker present AND no unexpected `Error|Fatal` in logs.
- **Read the first error, not the last.** Stop a phase on its first real failure and report it verbatim (tool, version, command, log excerpt).
- **Don't suppress warnings** to make logs look clean. Classify each one as a teaching-library limitation, a missing flow input, or a real problem.
- **Licensed data stays on CAE.** Don't copy `.db`, LEF, `.tf`, TLU+, or generated NDMs into any git repo or off the machine. Scripts may *reference* installed paths only.
- **Don't launch GUIs** (`design_vision`, `verdi`, `start_gui`). Those are for the human via Guacamole. Use Tcl/report equivalents.
- If a license check fails, save the exact diagnostic and tool version, then stop that phase.

---

## 1. Environment facts (verified by handout author)

| Item | Value |
|---|---|
| Env setup | `module load synopsys/suite`, then `synopsys-run` (enters container, prompt `synopsys>`) |
| Order | Module **before** container, every new shell. A "CAE launcher warning" means the module wasn't loaded. |
| VCS / Verdi / DC / PT | Y-2026.03 under `/srv/auto/apps/synopsys-2026/{vcs,verdi,syn,prime}/Y-2026.03/bin/` |
| ICC2 | **X-2025.06-SP3** at `/srv/auto/apps/synopsys-2026/icc2/X-2025.06-SP3/bin/icc2_shell` (older than DC!) |
| SAED32 EDK root | `/srv/auto/apps/saed32_edk/2023` (readable) |
| SAED32 PDK dir | **Permission denied** for normal accounts. Don't depend on it. |
| Teaching corner | RVT, TT, 1.05 V, 25 C → `saed32rvt_tt1p05v25c.db` |
| Tech file | `$EDK/tech/milkyway/saed32nm_1p9m_mw.tf` |
| Cell LEF | `$EDK/lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/lef/saed32nm_rvt_1p9m.lef` |
| Timing db | `$EDK/lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt/db_nldm/saed32rvt_tt1p05v25c.db` |
| SSH host | Handout says `best-tux.cae.wisc.edu`; CAE's Aug 2026 KB changes point to `best-linux.cae.wisc.edu`. Home dir is shared across hosts. |

### 1a. Non-interactive container use (VERIFY FIRST)

`synopsys-run` is documented as an interactive shell. Before anything else, figure out how to run commands inside it non-interactively:

```bash
bash -lc 'type module; module load synopsys/suite; type synopsys-run; cat "$(command -v synopsys-run)" 2>/dev/null | head -50'
```

Try, in order, and use the first that works:

1. `bash -lc 'module load synopsys/suite && synopsys-run command -v vcs dc_shell icc2_shell icc2_lm_shell pt_shell verdi urg'`
2. `bash -lc 'module load synopsys/suite && synopsys-run bash -lc "command -v vcs dc_shell icc2_shell icc2_lm_shell"'`
3. Pipe a script into its stdin: `synopsys-run < script.sh`

Record which pattern works at the top of the report. All commands below are "inside the container" unless stated otherwise.

**Phase 1 pass:** all of `vcs dc_shell verdi icc2_shell icc2_lm_shell pt_shell urg` resolve to paths.

---

## 2. Get the companion code

```bash
[ -d ~/cae-synopsys-guides ] || git clone https://github.com/abhinavnandwani/cae-synopsys-guides.git ~/cae-synopsys-guides
cd ~/cae-synopsys-guides/lab && ls -lh
cat rtl/sb_flop.v
sed -n '1,100p' tb/tb.sv
```

Expected: `rtl/sb_flop.v` (1-bit reg, **synchronous active-high reset**), `tb/tb.sv` (top `tb`, instance `dut`), `run_lab.py`, `synth/run.tcl`, `physical/build_reference.tcl`, `physical/floorplan.tcl`.

Design top = `sb_flop`. Sim top = `tb`. Don't mix them up.

---

## 3. Simulation + coverage + negative test

```bash
cd ~/cae-synopsys-guides/lab
python3 run_lab.py simulation 2>&1 | tee runs/_last_sim_stdout.log
```

Capture the printed `RUN_DIRECTORY`, then from inside it:

```bash
grep -nE 'Error|Fatal|Warning' compile.log
grep -nE 'UVM_INFO|SB_SNPS_SIM_PASS|\$finish at' simulate.log
tail -n 10 negative/expected_failure.log
cat result.json
```

**Pass criteria (all must hold):**
- Runner prints `LAB_RESULT=PASS`.
- `simulate.log` contains `SB_SNPS_SIM_PASS` and the UVM `[ACCESS]` info line.
- `negative/expected_failure.log` contains `data failed` at **21000 ps** and does **not** contain `SB_SNPS_SIM_PASS`.
- Files exist: `simv`, `smoke.fsdb`, `simv.vdb/`, `coverage_report/dashboard.html`.

**Expected coverage (DUT `tb.dut`, module `sb_flop`):** line 100%, branch 100%, toggle 87.5%. The missing bin is the `rst` 0→1 transition, because the test starts in reset and never reasserts it. Extract it with:

```bash
grep -rlE 'sb_flop' coverage_report/ | head
# or regenerate a text report:
urg -full64 -dir simv.vdb -format text -report cov_text > urg_text.log 2>&1 && ls cov_text
```

(`-format text` is standard URG. If it errors, note it and skip.)

### Manual reproduction (optional, only if the runner fails)

```bash
SB_LAB="$HOME/cae-synopsys-guides/lab"
SB_RUN=$(mktemp -d "$SB_LAB/runs/manual-sim-XXXXXX"); cd "$SB_RUN"
export VERDI_HOME="$(dirname "$(dirname "$(command -v verdi)")")"
vcs -full64 -sverilog -timescale=1ns/1ps -ntb_opts uvm-1.2 -debug_access+all -kdb \
    -cm line+cond+tgl+branch+assert "$SB_LAB/rtl/sb_flop.v" "$SB_LAB/tb/tb.sv" \
    -top tb -o simv > compile.log 2>&1
# STOP here if compile.log has errors (the shell won't stop for you)
./simv -cm line+cond+tgl+branch+assert > simulate.log 2>&1
./simv -cm line+cond+tgl+branch+assert +INJECT_FAILURE > negative.log 2>&1
urg -full64 -dir simv.vdb -report coverage_report > coverage.log 2>&1
```

---

## 4. Synthesis (Design Compiler)

```bash
cd ~/cae-synopsys-guides/lab
python3 run_lab.py synthesis 2>&1 | tee runs/_last_synth_stdout.log
```

In the printed `RUN_DIRECTORY`:

```bash
grep -nE 'Error|Warning' synthesis.log
cat area.rpt timing.rpt constraints.rpt constraints.sdc mapped.v
```

**Pass criteria:**
- Outputs exist: `mapped.v`, `mapped.ddc`, `constraints.sdc`, `area.rpt`, `timing.rpt`, `constraints.rpt`.
- 2 mapped cells: `q_reg` = `DFFSSRX1_RVT`, plus a tie-low cell `U5` (`logic_0`). Cell area **7.116032**.
- Max-delay path: startpoint `rst` → endpoint `q_reg`, arrival ~1.01 ns, required ~9.88 ns, slack **8.86 ns**.
- `constraints.rpt` has no violators.

Constraints are the teaching set: 10 ns clock, 1 ns input delay on `{rst d}`, 1 ns output delay on `q`.

Export the path for later phases:

```bash
export SB_SYNTH_RUN="<absolute path of this synthesis RUN_DIRECTORY>"
```

---

## 5. ICC2 reference library (the Milkyway → NDM fix)

**Background:** prior attempts died converting SAED32 *Milkyway libraries* to NDM, because `icc2_lm_shell` needs a legacy `icc_shell` binary for that conversion, and CAE doesn't ship `icc_shell`. The fix is to never convert Milkyway libraries. Build the NDM from `.tf` + `.db` + LEF with `create_workspace`. This is verified working on CAE.

```bash
SB_LAB="$HOME/cae-synopsys-guides/lab"
SB_PHYS=$(mktemp -d "$SB_LAB/runs/physical-XXXXXX"); cd "$SB_PHYS"
echo "$SB_PHYS" > "$SB_LAB/runs/_last_phys_dir"
icc2_lm_shell -f "$SB_LAB/physical/build_reference.tcl" > library.log 2>&1
grep -nE 'Error|Warning|frames' library.log
ls -d sb_rvt.ndm
```

Core of the script, for reference:

```tcl
set edk /srv/auto/apps/saed32_edk/2023
set cells $edk/lib/stdcell_rvt/SAED32_EDK/lib/stdcell_rvt
create_workspace -technology $edk/tech/milkyway/saed32nm_1p9m_mw.tf -flow normal sb_rvt
read_db  $cells/db_nldm/saed32rvt_tt1p05v25c.db
read_lef $cells/lef/saed32nm_rvt_1p9m.lef
check_workspace
commit_workspace -output sb_rvt.ndm
```

**Pass criteria:** `check_workspace` succeeds, **294 frames** created, `sb_rvt.ndm` exists. Stop if either check fails.

**Expected warnings (record, don't suppress):**
1. A technology-layer warning.
2. A LEF bus-character warning.
3. Large M1 routing blockages in cell abstracts. This may hurt pin access at detailed route later.

---

## 6. Import + floorplan + initial placement

In the same `$SB_PHYS` dir, with `SB_SYNTH_RUN` exported:

```bash
icc2_shell -f "$SB_LAB/physical/floorplan.tcl" > floorplan.log 2>&1
grep -nE 'Error|Warning|REGISTER_|FLOORPLAN_DONE' floorplan.log
ls -d sb_flop.dlib
```

The script does: `create_lib -ref_libs {sb_rvt.ndm} sb_flop.dlib` → `read_verilog -top sb_flop mapped.v` → `link_block` → `read_sdc` → `initialize_floorplan -control_type die -boundary {{0 0} {20 20}} -core_offset 2` → `create_placement -floorplan` → `save_block` / `save_lib`.

Note: ICC2 gets `mapped.v`, **not** `mapped.ddc`. DC is 2026.03 and ICC2 is 2025.06-SP3, so don't feed newer DC databases to older ICC2.

**Pass criteria:**
- Successful link message, and `FLOORPLAN_DONE` marker present **with no earlier errors**. The marker only means the script reached the end.
- `q_reg`: origin ≈ `{8.0387 8.7512}`, orientation `R0`, `physical_status` = `placed`. Exact coords may shift; the status matters.
- `sb_flop.dlib` saved and reopenable:

```bash
cat > reopen.tcl <<'EOF'
open_lib sb_flop.dlib
open_block sb_flop
puts "ORIGIN [get_attribute [get_cells q_reg] origin]"
puts "STATUS [get_attribute [get_cells q_reg] physical_status]"
puts "PINS [get_object_name [get_pins q_reg/*]]"
exit
EOF
icc2_shell -f reopen.tcl > reopen.log 2>&1; grep -E 'ORIGIN|STATUS|PINS|Error' reopen.log
```

**Expected:** ICC2 reports that it **derived missing preferred routing directions**. The `.tf` doesn't define them. This must be resolved before routing (see 7a).

---

## 7. Beyond the handout: scout the path to a routed design

Everything in this section is **unverified on CAE**. Investigate, try, and report. Don't claim success without log evidence. Confirm any command's syntax with `help -verbose <cmd>` or `man <cmd>` in this exact ICC2 version before relying on it. Work in a **copy** of the physical run dir so the phase-6 checkpoint stays intact.

### 7a. Routing directions
- Query what ICC2 derived: `get_attribute [get_layers] routing_direction` (per layer, M1–M9).
- Find authoritative directions: look for a technology LEF in the EDK with `find /srv/auto/apps/saed32_edk/2023 -iname '*tech*.lef' -o -iname '*.lef' | head -50`, then check `DIRECTION` in its `LAYER` sections. Also grep the `.tf` for layer blocks.
- Set them explicitly, e.g. `set_attribute [get_layers {M1 M3 ...}] routing_direction horizontal`, **only after** confirming the convention from the tech data. Report whether derived and authoritative directions agree.

### 7b. Parasitic tech (TLU+)
The handout lists RC tech as a required input but never loads it. Locate it:

```bash
find /srv/auto/apps/saed32_edk/2023 \( -iname '*tluplus*' -o -iname '*.tluplus' -o -iname '*.itf' -o -iname '*map*' \) 2>/dev/null | head -50
```

Expect Cmax/Cmin (or nominal) TLU+ files plus a layer map (tf↔ITF). Then try `read_parasitic_tech -tlup <file> -layermap <map> -name <nom>` and report which files and corners exist.

### 7c. Scenario setup
Try a minimal single scenario: `create_mode`, `create_corner`, `create_scenario -mode .. -corner .. -name ..`, `current_scenario`, `read_sdc` into it, and `set_parasitic_parameters` pointing at the TLU+ name. Report `report_scenarios` output.

### 7d. Power, place, CTS, route (stretch)
Attempt in order, stopping at the first hard failure:
1. PG nets and connections: `create_net -power VDD`, `create_net -ground VSS`, `connect_pg_net -automatic`. Check the cell LEF for actual PG pin names first.
2. Simple PG: rails/mesh via `create_pg_mesh_pattern` / `set_pg_strategy` / `compile_pg`, or `create_pg_std_cell_conn_pattern` for rails.
3. `place_opt`, then `check_legality`.
4. `clock_opt`. A 1-flop design is trivial; the point is exercising the flow.
5. `route_auto` or `route_opt`, then `check_routes`. Watch for M1 pin-access issues tied to the blockage warning from phase 5.
6. `report_timing`, `report_qor`.

The die is 20×20 with 1 cell, so if placement or PG complains about geometry, try a larger boundary before debugging anything else.

---

## 8. Final report

Write `~/cae-synopsys-guides/lab/runs/AGENT_REPORT.md` containing:

1. The non-interactive container invocation that worked (phase 1a).
2. Tool paths and versions actually observed.
3. Per phase (3–6): run directory, PASS/FAIL against the criteria above, measured numbers (coverage %, area, slack, frame count, q_reg origin/status), and every warning with its classification.
4. Phase 7 findings: routing-direction table (derived vs. authoritative), TLU+/layermap file paths found, scenario result, and how far 7d got, with the first blocking error verbatim.
5. Any deviations from this runbook and why.

Don't delete run directories. The human will open `smoke.fsdb` in Verdi, `mapped.ddc` in Design Vision, and `sb_flop.dlib` in the ICC2 GUI via Guacamole to cross-check.
