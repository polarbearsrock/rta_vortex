# Frozen Unified DPA16 results

These archives retain the exact preprocessed RTL and original synthesis reports
for the selected DPA/UCC implementations, matched standalone arithmetic blocks,
and all twelve coefficient-bank candidates. They complement the current source
under `hw/rtl/ucc`; a frozen measurement is not silently reassigned to later RTL.

Each per-top archive contains `design.sv`, the source/configuration manifest,
area and hierarchical-area reports, timing, QoR, vectorless power, mapped SDC,
the completion marker and the synthesis Tcl. `verification.tar.gz` contains
passed RTL/protocol/directed-test evidence and corresponding mapped-check
manifests/results. Large generated vectors are identified by hashes and can be
regenerated using the test scripts. Early historical measurements not listed in
this archive index remain documented in the parent result summaries.

[index.json](index.json) lists every archive, its SHA256, the SHA256 of each
contained file, and its measured PPA. Archives use deterministic metadata and
are checked after creation. PDK models, EDA binaries, mapped netlists and build
executables are not included. Test manifests retain the original machine paths
as execution provenance; they are not portable installation requirements.

Start with these reports:

- [Architecture and reproduction](../unified_dpa16.md)
- [Original PPA comparison](../ucc_ppa_interim.md)
- [Exact FMA resource-reuse experiment](../ucc_segmented_fma.md)
- [EXP coefficient sharing comparison](../ucc_coeff_sharing.md)

The exact UCC selected after the FMA follow-up is
`VX_ucc_v4_window_comb` at 39,430.188 um2 and 5.000 ns. The smallest standalone
coefficient bank per PE is the four-port plane candidate at 295.533 um2/PE;
that table experiment is not integrated into the full UCC. Native regular and
compact EXP variants retain their separately documented numerical policies.

To inspect a bundle, run `tar -xzf <top>.tar.gz` outside the source tree. To
re-synthesize its frozen `design.sv`, use the extracted `synth.tcl` with
`UCC_TOP=<top>` and `UCC_RUN_DIR=<absolute extracted directory>` in an environment
with the documented Genus and TSMC setup. The setup paths in that Tcl may need
local adjustment. The normal `hw/syn/ucc/run.sh` instead synthesizes current RTL.
The archived constraints are 5 ns combinational, 50 ps input slew, 5 fF output
load and ZeroWireload; they do not prove post-route timing or a 1 GHz pipeline.

Regenerate these bundles from completed local runs with
`python3 hw/syn/ucc/export_results.py`. The exporter validates measurements and
refuses to overwrite an archive with different contents.
