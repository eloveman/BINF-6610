#!/bin/bash -l
#SBATCH --job-name=vc-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/persample_%A_%a.out
# Stages 0-5 for ONE sample, run inside the container image.
# Array task N runs samplesheet row N.
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

# Row N below the header: the + 1 skips the header line.
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

# Deliberate-failure switch from week 2, off unless you pass FAIL_TASK.
[[ "${SLURM_ARRAY_TASK_ID}" != "${FAIL_TASK:-}" ]] \
    || { echo "task ${SLURM_ARRAY_TASK_ID}: failing on purpose (FAIL_TASK)" >&2; exit 1; }

export THREADS="${SLURM_CPUS_PER_TASK}"

# Temporary files on the node's own disk, removed however the job ends.
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "task ${SLURM_ARRAY_TASK_ID}: ${SAMPLE} on $(hostname), ${THREADS} cores, image ${SIF}" >&2

# --cleanenv: nothing from this shell gets in except the --env lines.
# --bind: the container also sees the course data and my scratch space.
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"
