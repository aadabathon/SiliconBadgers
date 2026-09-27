# ICC2 on CAE: findings (updated 2026-09-24)

**Everything is in [`SYNOPSYS_CAE_GUIDE.md`](SYNOPSYS_CAE_GUIDE.md).** This file is a short summary.

- **Status:** Adam16 passes every stage from a clean start in 5m42s with `saed32_icc2_kit/run.sh <dir>`. The stages are NDM → DC → ICC2 → PrimeTime → Formality ×2 → VCS (RTL, gate, gate+SDF) → GDS.
  - PrimeTime at 3.0 ns (ss0p95v125c): setup +0.004 ns, hold +0.060 ns.
  - Formality: RTL ≡ synth netlist ≡ routed netlist (232/232).
  - Gate+SDF simulation matches RTL cycle for cycle, with 0 timing violations.
- **The fix:** build the NDM in `icc2_lm_shell` from the stock 2023 Milkyway techfile, the cell LEF under `SAED32_EDK/lib/stdcell_rvt/lef/`, and the kit `.db`.
  - The top-level `lib/stdcell_rvt/lef/*.lef` is a tech-only LEF (0 macros).
  - The 2022 prebuilt NDMs are a mismatched cell release, and all their delays evaluate to `??`.
  - Synthesize with the kit `.db` so cell names are `*_RVT`.
- **Corrections to the 2026-09-23 version of this file:**
  - The kit now uses only 2023 paths.
  - The 189–192 route DRCs are *not* a track/floorplan issue. They come from SAED32 M1 pins sitting off the VIA1 track grid (guide §9). A track-aligned core offset (now 4.864) and every router grid option were tried, and none of them removed them.
  - The headless screenshot is no longer part of `all`.
- **Open items:** guide §9 (DRCs, FSM coverage, SRAM macro placement), plus running the companion lab and Adam's own testbenches, which were blocked for the agent.
