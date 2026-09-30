#!/usr/bin/env bash
# Two submissions and one dependency. Run it from inside slurm/:
#   bash submit.sh          every row of the samplesheet, then the cohort job
#   bash submit.sh 4,7      tasks 4 and 7 only, then the cohort job
set -euo pipefail

[[ -f conf/slurm.env ]] || { echo "run submit.sh from inside slurm/ (no conf/slurm.env here)" >&2; exit 64; }
source conf/slurm.env
mkdir -p logs               # Slurm will not create the log folder itself

N=$(awk -F',' 'NR > 1 && NF > 0' "${SAMPLESHEET}" | wc -l | tr -d ' ')
RANGE=${1:-1-${N}}

ARRAY_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --array="${RANGE}" 01_persample.sbatch)
ARRAY_ID=${ARRAY_ID%%;*}

# afterok: only if EVERY task succeeded. kill-on-invalid-dep: if one fails,
# cancel the cohort job instead of leaving it pending forever.
COHORT_ID=$(sbatch --parsable -p "${PARTITION}" -A "${ACCOUNT}" \
    --dependency=afterok:${ARRAY_ID} --kill-on-invalid-dep=yes 02_cohort.sbatch)
COHORT_ID=${COHORT_ID%%;*}

echo "array ${ARRAY_ID} (tasks ${RANGE}), then cohort ${COHORT_ID}" >&2
echo "watch with: squeue -u ${USER}      results: ${RUN_ROOT}/results" >&2
