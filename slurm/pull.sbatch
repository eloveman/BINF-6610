#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o pull-%j.out
# Fetch the image onto Explorer as a .sif, by its digest. A job, because the
# conversion needs more memory than the login node allows.
set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers "${APPTAINER_CACHEDIR}"
apptainer pull --force /scratch/${USER}/containers/variant-call.sif \
    docker://eloveman1/variant-call@sha256:66cf97febd9970f21ab5a8c3cee45f7940e68d4b6875053a56754d1423a9a21d
