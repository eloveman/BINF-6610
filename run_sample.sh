#!/usr/bin/env bash
# ONE sample, stages 0-5. An array task calls this for its sample.
#   ./run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]
# Stages 6-9 need every sample at once, so this refuses them.
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RUN_STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)
export RUN_STARTED

SHEET=${1:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
OUT=${2:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
SAMPLE=${3:?usage: run_sample.sh <samplesheet.csv> <outdir> <sample_id> [last-stage]}
LAST=${4:-quantify}

source "${HERE}/lib/common.sh"
for f in "${HERE}"/stages/*.sh; do source "$f"; done

case "$LAST" in
    validate|qc_raw|trim|align|postprocess|quantify) ;;
    *) die "run_sample.sh runs stages 0-5 only; '${LAST}' needs every sample -- use run_pipeline.sh" ;;
esac

check_columns
[[ -n "$(rows)" ]] || die "sample '${SAMPLE}' is not in ${SHEET}"
make_dirs
run_stages validate "$LAST"
