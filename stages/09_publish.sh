#!/usr/bin/env bash
# 9 · publish — manifest.json: the commit, samples, reference, region, tools
set -euo pipefail

stage_publish() {
    # Use the SAME arguments that worked in your week-1 run. If the page
    # "Week 2 — Your manifest on Explorer" gives a new write_manifest.sh,
    # put it in lib/ and follow its usage line.
    PIPELINE_NAME=variant-call \
        bash "${HERE}/lib/write_manifest.sh" "${RES}" "${SHEET}" "${REF}" "${REGION}"

    [[ -s "${RES}/manifest.json" ]] || die "write_manifest.sh wrote no manifest.json"
    log "results in ${RES}:"
    ls -1 "$RES" >&2
}
