#!/usr/bin/env bash
# Every sample, stages 0-9.
#   ./run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]
# FROM=<stage> starts later than stage 0; the cohort job uses FROM=merge,
# because the array tasks have already run stages 0-5.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
export RUN_STARTED

SHEET=${1:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
OUT=${2:?usage: run_pipeline.sh <samplesheet.csv> <outdir> [last-stage]}
LAST=${3:-publish}
FROM=${FROM:-validate}
SAMPLE=""            # empty: every row of the samplesheet

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do source "$f"; done

check_columns
make_dirs
run_stages "$FROM" "$LAST"
