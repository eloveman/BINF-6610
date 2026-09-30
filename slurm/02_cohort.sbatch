#!/bin/bash -l
#SBATCH --job-name=vc-cohort
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --time=01:00:00
#SBATCH --export=NONE
#SBATCH --output=logs/cohort_%j.out
# Stages 6-9, once, over every sample. submit.sh starts it only after every
# array task has succeeded (afterok).
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

export THREADS="${SLURM_CPUS_PER_TASK}"

export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

set +u      # the module and conda activation scripts read unset variables
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

echo "cohort job on $(hostname), ${THREADS} cores, TMPDIR=${TMPDIR}" >&2
# FROM=merge: stages 0-5 were done by the array tasks.
FROM=merge bash "${PIPELINE_DIR}/run_pipeline.sh" "${SAMPLESHEET}" "${RUN_ROOT}"

CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
