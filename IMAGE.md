# Image

## Base image
mambaorg/micromamba:2.0.5-ubuntu24.04
mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5

## Versions pinned
bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1

## The pushed image
docker.io/eloveman1/variant-call@sha256:paste-the-64-characters-here

To rerun this analysis in a year, three things are needed: the same software,
the same code, and the same inputs. The software is the pushed image, and the
digest under **The pushed image** is what gets it back exactly: the tag `1.0`
can be moved to a different image, and `/scratch`, where the `.sif` lived, is
emptied every month, but `apptainer pull docker://…@sha256:…` with that digest
always returns the identical image. The recipe in `containers/Dockerfile`, with
the base image and versions under **Base image** and **Versions pinned**, says
how the image was made, but rebuilding from it would not be byte-identical,
because everything not pinned is resolved again on build day. The code is the
commit recorded as `git_sha` in `cluster-run-container/manifest.json`, and the
inputs are the samplesheet and the GRCh38 reference it names.
