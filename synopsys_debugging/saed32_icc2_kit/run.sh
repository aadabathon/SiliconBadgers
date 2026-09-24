#!/bin/bash
# RTL -> GDS on CAE Linux (Fall 2026 module/container system).
# Usage:  run.sh <work_dir> [ndm|synth|apr|sta|lec|sim|shot|all]
#         all = ndm (if missing) -> synth -> apr -> sta -> lec -> sim
#         'shot' (headless GUI screenshot) is never part of 'all'.
# Edit config.tcl for your design first.
set -o pipefail   # no -u: Lmod's init scripts reference unset vars
KIT="$(cd "$(dirname "$0")" && pwd)"
WORK="${1:?usage: run.sh <work_dir> [ndm|synth|apr|sta|lec|sim|shot|all]}"
STEP="${2:-all}"
mkdir -p "$WORK" && cd "$WORK" || exit 1

# Lmod: must be loaded in THIS shell (not in a pipe/subshell).
source /etc/profile.d/95-lmod.sh 2>/dev/null || true
module load synopsys/suite >/dev/null 2>&1
case "$(command -v icc2_shell)" in /srv/auto/apps/*) ;; *) echo "module load synopsys/suite failed (icc2_shell=$(command -v icc2_shell))"; exit 1;; esac

run() { local log=$1; shift; echo ">> $* (log: $WORK/$log)"; synopsys-run "$@" > "$log" 2>&1 < /dev/null; }

if [[ $STEP == ndm || ( $STEP == all && ! -d $KIT/ndm/saed32rvt.ndm ) ]]; then
  run ndm.log icc2_lm_shell -f "$KIT/build_ndm.tcl"; grep -E "NDM_(OK|FAIL)" ndm.log
fi
if [[ $STEP == synth || $STEP == all ]]; then
  run synth.log dc_shell -f "$KIT/synth.tcl"; grep -E "SYNTH DONE|^Error" synth.log | head
fi
if [[ $STEP == apr || $STEP == all ]]; then
  run apr.log icc2_shell -f "$KIT/apr.tcl"; grep -E "APR DONE|^Error|Segmentation" apr.log | head
fi
if [[ $STEP == sta || $STEP == all ]]; then
  run sta.log pt_shell -f "$KIT/sta.tcl"; grep -E "STA_RESULT|STA DONE|^Error" sta.log | head
fi
if [[ $STEP == lec || $STEP == all ]]; then
  for i in synth apr; do
    IMPL=$i run lec_$i.log fm_shell -f "$KIT/lec.tcl"; grep -E "LEC_RESULT|^Error" lec_$i.log | head -3
  done
fi
if [[ $STEP == sim || $STEP == all ]]; then
  echo ">> vcs/urg via sim.sh (logs: $WORK/sim/)"
  synopsys-run bash "$KIT/sim.sh" < /dev/null 2>&1 | grep -E "^(SIM_|TRACE|NEGATIVE|ACTIVITY|SDF)"
fi
if [[ $STEP == shot ]]; then
  # Xvfb on the host; synopsys-run forwards $DISPLAY and binds /tmp/.X11-unix.
  D=":$((100 + RANDOM % 400))"
  env -i PATH=/usr/bin:/bin Xvfb "$D" -screen 0 1920x1200x24 -nolisten tcp >/dev/null 2>&1 & XP=$!
  for _ in $(seq 50); do [[ -S /tmp/.X11-unix/X${D#:} ]] && break; sleep 0.2; done
  export DISPLAY="$D"; run shot.log icc2_shell -f "$KIT/screenshot.tcl"; kill $XP 2>/dev/null
  grep -E "SCREENSHOT DONE|^Error" shot.log
fi
