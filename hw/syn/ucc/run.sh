#!/usr/bin/env bash
set -euo pipefail
ucc_root=$(cd "$(dirname "$0")/../../.." && pwd)
ucc_top=${1:-VX_ucc_dpa16_comb}
python3 "$ucc_root/hw/unittest/ucc/run.py" prepare-synth --top "$ucc_top"
export UCC_TOP=$ucc_top
export UCC_RUN_DIR="$ucc_root/build_ucc/ucc_synth/$ucc_top"
# The vendor environment script references variables that may be unset.
set +u
source /data/eda_tools/cadence/bashrc/genus.bashrc
set -u
export CDS_LIC_FILE=${CDS_LIC_FILE:-27006@cadencels.s.uw.edu}
cd "$UCC_RUN_DIR"
rm -f complete.txt
cp "$ucc_root/hw/syn/ucc/synth.tcl" synth.tcl
genus -batch -files "$UCC_RUN_DIR/synth.tcl" -log genus > run.log 2>&1
test -f complete.txt
