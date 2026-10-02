# The pipeline's software, pinned to the versions in the course conda
# environment (conda env export -p /courses/BINF6610.202710/shared/env/binf6610).
# Build for Explorer's CPU:
#   docker build --platform linux/amd64 -t DOCKERHUB_USER/variant-call:1.0 containers/
FROM mambaorg/micromamba:2.0.5-ubuntu24.04

RUN micromamba install --yes --name base \
        --channel conda-forge --channel bioconda \
        bwa=0.7.19 \
        samtools=1.24 \
        bcftools=1.24 \
        gatk4=4.6.2.0 \
        fastqc=0.12.1 \
        fastp=1.3.7 \
        multiqc=1.35 \
        git=2.47.1 \
    && micromamba clean --all --yes

# apptainer exec does not run the image's activation script, so put the
# tools on PATH directly.
ENV PATH=/opt/conda/bin:$PATH
