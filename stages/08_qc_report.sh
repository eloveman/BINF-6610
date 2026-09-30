#!/usr/bin/env bash
# 8 · qc_report — MultiQC over every log this run produced
set -euo pipefail

stage_qc_report() {
    multiqc -q -f -o "$RES" "$QC" "$LOG" > "${LOG}/multiqc.log" 2>&1
    [[ -s "${RES}/multiqc_report.html" ]] || die "multiqc produced no report"
    log "QC report written"
}
