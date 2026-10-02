#!/bin/bash -l
#SBATCH --job-name=vc-persample
#SBATCH --partition=courses
#SBATCH --account=binf6610.202710
#SBATCH --cpus-per-task=8
#SBATCH --mem=16G
#SBATCH --time=00:30:00
#SBATCH --export=NONE
#SBATCH --output=logs/persample_%A_%a.out
# Stages 0-5 for ONE sample. Array task N runs samplesheet row N.
set -euo pipefail

source "${SLURM_SUBMIT_DIR}/conf/slurm.env"

# Row N below the header: the + 1 skips the header line.
SAMPLE=$(awk -F',' -v n="${SLURM_ARRAY_TASK_ID}" 'NR == n + 1 { print $1 }' "${SAMPLESHEET}")
[[ -n "${SAMPLE}" ]] || { echo "task ${SLURM_ARRAY_TASK_ID}: no row ${SLURM_ARRAY_TASK_ID} in ${SAMPLESHEET}" >&2; exit 64; }

# Deliberate-failure switch for TROUBLESHOOTING.md, off unless you pass it:
#   sbatch --export=NONE,FAIL_TASK=2 --array=2 01_persample.sbatch
[[ "${SLURM_ARRAY_TASK_ID}" != "${FAIL_TASK:-}" ]] \
    || { echo "task ${SLURM_ARRAY_TASK_ID}: failing on purpose (FAIL_TASK)" >&2; exit 1; }

export THREADS="${SLURM_CPUS_PER_TASK}"

# Temporary files on the node's own disk, removed however the job ends.
export TMPDIR="/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

set +u      # the module and conda activation scripts read unset variables
module load miniconda3/25.9.1
source activate "${CONDA_ENV}"
set -u

echo "task ${SLURM_ARRAY_TASK_ID}: ${SAMPLE} on $(hostname), ${THREADS} cores, TMPDIR=${TMPDIR}" >&2
bash "${PIPELINE_DIR}/run_sample.sh" "${SAMPLESHEET}" "${RUN_ROOT}" "${SAMPLE}"

# The kernel's exact memory high-water mark, for RESOURCES.md.
CG=/sys/fs/cgroup$(awk -F: '/^0::/{print $3}' /proc/self/cgroup)
echo "memory.peak: $(cat "$CG/memory.peak" 2>/dev/null || echo unavailable)" >&2
