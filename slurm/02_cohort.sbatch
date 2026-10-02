#!/bin/bash -l
#SBATCH --job-name=vc-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=2
#SBATCH --mem=4G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/cohort_%j.out
# Stages 6-9, once, over every sample, run inside the container image.
# submit.sh starts it only after every array task has succeeded (afterok).
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

echo "cohort job on $(hostname), ${THREADS} cores, image ${SIF}" >&2

# FROM=merge: stages 0-5 were done by the array tasks. It must be passed with
# --env, because --cleanenv would drop it otherwise.
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --env FROM=merge \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"
