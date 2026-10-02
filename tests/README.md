# Assignment 3 — Your variant-calling pipeline, in an image you built

Due one week from the session. Submit a link to the same Git repository as weeks 1 and 2.

Last week your pipeline ran on Explorer inside the course conda environment. Both of your job scripts
activate that environment and then run one line — and that one line is where the software came from.
This week the software comes from an image **you** build, and the pipeline itself does not change.

## What you are adding

```
your-repo/
├── containers/
│   └── Dockerfile            # your image's recipe
├── slurm/
│   ├── 01_persample.sbatch   # last line changed
│   ├── 02_cohort.sbatch      # last line changed
│   └── pull.sbatch           # new: fetch your image onto Explorer
├── cluster-run/              # last week's conda run, unchanged
├── cluster-run-container/    # this week's run, through your image
├── IMAGE.md                  # what you built, and how to prove it
└── TROUBLESHOOTING.md        # four failures you caused on purpose
```

One line is also added to your stage 9 (step 6). Nothing else in your pipeline changes.

## Before you start

- **Docker, on your laptop.** The **Week 3 — Pre-flight** page walks through installing it and ends
  with two short checks. Do it before the session.
- **A Docker Hub account** at <https://hub.docker.com> — free. It is where your image lives so that
  Explorer can fetch it. The first `docker push` creates the repository with your account's default
  visibility (Docker Hub → Settings → Default privacy). Keep it public: the pull job on Explorer
  downloads it without logging in.

## The steps

### 1 · Write `containers/Dockerfile`, pinned to the course environment

Your image must contain the tools your pipeline runs, **at the versions the course conda environment
has**, so that switching from the environment to the image changes nothing about the software.

| tool | version |
|---|---|
| `bwa` | 0.7.19 |
| `samtools` | 1.24 |
| `bcftools` | 1.24 |
| `gatk4` | 4.6.2.0 |
| `fastqc` | 0.12.1 |
| `fastp` | 1.3.7 |
| `multiqc` | 1.35 |
| `git` | any version, pinned — stage 9 runs `git rev-parse`, and the image has no `git` unless you install one |

Take them from the environment rather than from this table. On Explorer:

```bash
module load miniconda3/25.9.1
conda env export -p /courses/BINF6610.202710/shared/env/binf6610 --no-builds \
    | grep -E '^  - (bwa|samtools|bcftools|gatk4|fastqc|fastp|multiqc)='
```

It prints the seven pins in `env.yml` format, `  - samtools=1.24` and so on. Paste them under
`dependencies:` in `containers/env.yml`, or write the same `tool=version` pairs on your
`RUN micromamba install` line. Add a pinned `git` yourself — the environment does not have one.

To see what else bioconda offers for a tool: `conda search --override-channels -c bioconda <tool>`.

The session's demo image is a working model: start `FROM mambaorg/micromamba:2.0.5-ubuntu24.04`,
install everything in one `RUN micromamba install ... && micromamba clean --all --yes`, and set
`ENV PATH=/opt/conda/bin:$PATH`. The test rejects three things that build fine today and differently
next month: a `FROM` with no tag or the tag `latest`, an `apt-get install` without `=version`, and a
tool named without `=version`.

You may list the pins in `containers/env.yml` instead and `COPY` it into the image, as the session
shows; the test reads pins from the `Dockerfile` and from any `.yml` beside it.

### 2 · Build it for Explorer's CPU, and look inside before it leaves your laptop

Explorer is `amd64`. Most laptops in the room are Apple Silicon, which is `arm64`, and an `arm64`
image builds without complaint and then refuses to run on the cluster. So always:

```bash
docker build --platform linux/amd64 -t <your-dockerhub-user>/variant-call:1.0 containers/
docker image inspect --format '{{.Architecture}}' <your-dockerhub-user>/variant-call:1.0    # amd64
```

Then run the version check from this archive inside it:

```bash
docker run --rm --platform linux/amd64 -v "$PWD/tests":/t <your-dockerhub-user>/variant-call:1.0 \
    bash /t/print_versions.sh
```

Every line should match the table. A laptop build takes about a minute and a half.

### 3 · Push it, and write down the digest

```bash
docker login
docker push <your-dockerhub-user>/variant-call:1.0
```

The last line of the output is the one you need:

```
1.0: digest: sha256:<64 hex characters> size: ...
```

That digest is the image's permanent name. The tag `1.0` can be pointed at a different image
tomorrow; the digest cannot. Pull by the digest. The push uploads about 850 MB, so on home internet
expect somewhere between five and twenty minutes.

### 4 · Fetch it onto Explorer, as a job

Converting the download into a `.sif` peaked at **7.8 GiB of memory** for a 1.1 GB image, and on the
login node all users' processes share one 6 GiB limit. So it is a job — `slurm/pull.sbatch`:

```bash
#!/bin/bash
#SBATCH -A binf6610.202710 -p courses
#SBATCH -c 4 --mem=16G -t 00:30:00
#SBATCH -o pull-%j.out
set -euo pipefail
export APPTAINER_CACHEDIR=/scratch/${USER}/apptainer-cache
mkdir -p /scratch/${USER}/containers
apptainer pull /scratch/${USER}/containers/variant-call.sif \
    docker://<your-dockerhub-user>/variant-call@sha256:<your digest>
```

`APPTAINER_CACHEDIR` is not optional: without it the download cache lands in your home directory,
whose quota is fixed and cannot be increased.

### 5 · Change the last line of each job script

This is the whole port. Each of your week-2 job scripts ends with one line that runs your pipeline,
and two lines above it activate the conda environment that line runs in. In the week-2 demo's
`01_persample.sbatch` they look like this — yours use your own variable names, such as
`${SAMPLESHEET}` if you followed the Assignment 2 page:

```bash
module load miniconda3/25.9.1                                     # delete
source activate "${CONDA_ENV}"                                     # delete
...
bash "${PIPELINE_DIR}/run_sample.sh" "${SHEET}" "${RUN_ROOT}/run" "${SAMPLE}" quantify
```

Delete the two conda lines, and put the container in front of the last one. Keep your own last line
as it is; only the `apptainer exec` part is new:

```bash
apptainer exec --cleanenv \
    --env THREADS="${THREADS}" \
    --env TMPDIR="${TMPDIR}" \
    --env SLURM_JOB_ID="${SLURM_JOB_ID}" \
    --env SLURM_CPUS_PER_TASK="${SLURM_CPUS_PER_TASK}" \
    --bind /courses/BINF6610.202710,/scratch/${USER} \
    "${SIF}" \
    bash "${PIPELINE_DIR}/run_sample.sh" "${SHEET}" "${RUN_ROOT}/run" "${SAMPLE}" quantify
```

Do the same to the last line of `02_cohort.sbatch` — the one that calls `run_pipeline.sh` — and add
`SIF=/scratch/${USER}/containers/variant-call.sif` to `conf/slurm.env`. What each piece is for:

- **`apptainer exec "${SIF}"`** runs the rest of the line inside your image, so `samtools` is the
  image's `samtools` rather than the environment's.
- **`--bind`**: without it, the container sees your home directory, `/tmp` and the directory you
  submitted from — each with everything below it — and nothing else of yours. Your code is in your
  home directory, so the container already sees it. Your run directory is under `/scratch/${USER}`,
  and the FASTQs and the reference are under `/courses`: those two are what `--bind` adds.
- **`--cleanenv`** starts the container with none of your shell's variables, so a stray setting in
  your login shell cannot change what the pipeline does.
- **The `--env` lines** carry chosen variables back in: `--env THREADS="${THREADS}"` sets `THREADS`
  inside to the value your job script set, because your shell replaces `${THREADS}` before
  `apptainer` starts. **Carry every variable your job script sets and your pipeline reads.** For the
  reference pipeline that is these four; find yours with
  `grep -rhoE '\$\{?[A-Z_]+' lib/ stages/ run_*.sh | sort -u`. Miss `THREADS` and nothing fails —
  your pipeline uses its own default instead of the cores you asked for.
- **The variables in the last line itself — `${SAMPLESHEET}` or `${SHEET}`, `${SAMPLE}` and the rest —
  need nothing**: the shell outside replaces them with their values before `apptainer` starts, so
  the container receives plain text.

### 6 · Your manifest records the container

If your stage 9 ends with the course's `write_manifest.sh` — the page [*Week 3 — Your manifest inside a container*](https://northeastern.instructure.com/courses/258265/pages/week-3-your-manifest-inside-a-container) — there is nothing to add. Inside a container, Apptainer sets
`APPTAINER_CONTAINER` to the path of the `.sif` it is running, under `--cleanenv` too, and the script
writes it into the manifest's `platform` block as `container`, which is what the test reads. If your
stage 9 writes a manifest of its own, switch to the script, or add a `container` field with that
value.

Two things it needs from this week's changes: `git` in your image, or `git_sha` comes out `unknown`;
and the two `--env SLURM_…` lines from step 5, or `slurm_job_id` and `slurm_cpus` come out `none`.

### 7 · Run the cohort, and commit what it produced

First point your run directory at a new folder — in `slurm/conf/slurm.env`, for example
`/scratch/${USER}/w3-run`. In last week's run directory every stage finds its output already there
and skips it, so nothing would run in your image. Then `bash slurm/submit.sh`, as last week, and
copy what it produced into a new directory, so that last week's run stays in `cluster-run/` for
step 9:

```bash
mkdir -p cluster-run-container
cp <your run>/results/cohort.filtered.vcf.gz  cluster-run-container/
cp <your run>/results/manifest.json           cluster-run-container/
```

If your `.gitignore` ignores VCFs, `git add -A` and `git add .` skip this one without a word. Add it
by name, with `-f`:

```bash
git add -f cluster-run-container/cohort.filtered.vcf.gz
```

### 8 · Compare the versions: the environment against your image

```bash
# on Explorer, in a shell on a compute node: on the login node gatk or multiqc can be killed
srun -A binf6610.202710 -p courses -c 2 --mem=4G -t 00:30:00 --pty bash
module load miniconda3/25.9.1
source activate /courses/BINF6610.202710/shared/env/binf6610

bash tests/print_versions.sh > cluster-run-container/versions-conda.txt

# the same script, inside your image
apptainer exec --cleanenv /scratch/${USER}/containers/variant-call.sif \
    bash tests/print_versions.sh > cluster-run-container/versions-image.txt

diff cluster-run-container/versions-conda.txt cluster-run-container/versions-image.txt
```

No output from `diff` means every tool in your image reports the same version as the environment you
used last week. **This is the check that is graded**, because it is the direct one: a matching
result does not prove matching software. The slide *Four runs, identical results* shows an image with
a different `fastp` whose 36,853 variant records were identical.

### 9 · Compare the records with last week's run

Last week's conda run is in `cluster-run/` and this week's is in `cluster-run-container/`. Compare only
the variant records: the header records the path each file was written to, so two runs never have
identical files. On Explorer, in the course environment:

```bash
{ bcftools view -H cluster-run/cohort.filtered.vcf.gz           | sha256sum    # last week, conda
  bcftools view -H cluster-run-container/cohort.filtered.vcf.gz | sha256sum    # this week, your image
} > cluster-run-container/records-sha256.txt
cat cluster-run-container/records-sha256.txt
```

**The two runs must use the same parameters**: the same samplesheet, the same reference, the same
pipeline code, and the same `--cpus-per-task`. The thread count is on that list because `bwa mem`
reads its input in batches of threads × 10 million bases and estimates the insert-size distribution
batch by batch, so a different thread count gives different batches and a few read pairs align
differently. Measured on one sample, 4 threads against 8: 6 read pairings differed, and the GVCF
differed by 2 records. With the same parameters, the two lines should be identical.

They do not have to match. If they differ, add one sentence to the file saying why:
`echo "They differ because …" >> cluster-run-container/records-sha256.txt`.

## If you cannot run Docker

Write the same recipe as an Apptainer definition file, `containers/variant-call.def`, and build it on
a compute node with `apptainer build` in a job — the slide *No Docker? The same recipe, built for
Apptainer in a job* has both files side by side. Everything from step 5 on is the same. In `IMAGE.md`,
under **The pushed image**, write `built from containers/variant-call.def by job <id>`. There is no
registry digest on this route, so say so plainly: the `.sif` is deleted with `/scratch` every month,
and a rebuild from the recipe will not be byte-identical.

## What to submit

- **`cluster-run-container/`** — `cohort.filtered.vcf.gz` and `manifest.json` from the containerised
  run, `versions-conda.txt`, `versions-image.txt` and `records-sha256.txt`. Leave `cluster-run/` as
  last week's run.
- **`IMAGE.md`** — these three headings, then one paragraph:

  ```markdown
  ## Base image
  mambaorg/micromamba:2.0.5-ubuntu24.04
  mambaorg/micromamba@sha256:1c62a28916ad7a4533555a542a5410e55ea2ed2c1e29f00c8fc3f1c8add111d5
  ## Versions pinned
  bwa=0.7.19 samtools=1.24 bcftools=1.24 gatk4=4.6.2.0 fastqc=0.12.1 fastp=1.3.7 multiqc=1.35 git=2.47.1
  ## The pushed image
  docker.io/<you>/variant-call@sha256:<the 64 hex characters docker push printed>
  <a paragraph: to rerun this in a year, what is needed, and which heading gives it?>
  ```

  The base image's digest is what `docker images --digests <base>` prints; the pushed image's is the
  last line `docker push` prints.
- **`TROUBLESHOOTING.md`** — the four failures below, a few lines each: the command, the output, the fix.

Do not commit the `.sif`: it is 1.2 GB, and `/scratch`, where it lives, is emptied on the first Tuesday
of every month. The pushed image's digest is what lets anyone pull the same image again.

## Four failures you cause on purpose

| | Break it | Write down |
|---|---|---|
| 1 | In a scratch directory, build `FROM ubuntu` (no tag) with `RUN apt-get update && apt-get install -y curl`; a day later rebuild with `docker build --pull --no-cache` | the two package lists (`docker run --rm <image> dpkg -l`) and every line that differs |
| 2 | Remove `--bind` from one job script and run one sample | where it stopped, what it printed, its exit code, and which path the container could not see |
| 3 | Remove the `--env THREADS=…` line from one job script and run one sample | how many threads your pipeline used — the `-t` on the `[main] CMD:` line that ends `bwa mem`'s log — against how many cores you asked for |
| 4 | On Explorer, `apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04`, then run anything out of it | whether the pull succeeded, and what the run said |

**Number 1 needs a day between its two builds**, so start it the night the assignment is set. A
plain rebuild is a cache hit and gives the identical image. `--pull` fetches `ubuntu` again, and
`--no-cache` re-runs the `apt-get` step even when `ubuntu` has not changed; use both.

**Number 3 is the one that matters**, because it stops nothing: the job finishes on the pipeline's own
default thread count, and only the log shows it. Number 2 stops at once — the lesson there is which
path the container could not see.

**If a breakage does not do what you expected, write that down instead.** "I aimed at X, got Y,
here is why" is a full-marks answer.

## How it is graded

**100 points, eight acceptance tests.** They are in `tests/`, they run on your laptop, and you run
them before you submit:

```bash
bash tests/run_acceptance.sh .
```

| Pts | Test | Full marks | Partial |
|---:|---|---|---|
| 15 | every version is pinned | the seven tools `=version`, the base image tagged and not `latest`, no bare `apt-get install` | **10** — one thing unpinned; **5** — the base image is `latest` |
| 20 | the versions inside your image match the course environment | all seven lines of `versions-image.txt` match | **10** — five or six of seven |
| 5 | the image is fetched by a job | `pull.sbatch` (or a build job) has `#SBATCH` lines and moves `APPTAINER_CACHEDIR` out of your home | — |
| 15 | both job scripts run the pipeline through the image | both last lines are wrapped in `apptainer exec` with `--cleanenv` and `--bind`, and no conda is activated | **10** — one script, or one of the two flags missing |
| 10 | the job's variables reach the container | `THREADS` and every other variable your pipeline reads carried in by name | **5** — some of them |
| 15 | the cohort ran through the image | `cluster-run-container/` holds the VCF, a manifest whose `container` names a `.sif`, and both record checksums — with one sentence if they differ | **10** — the run, without both checksums or the sentence; **5** — the VCF and manifest, but no `container` field |
| 10 | `IMAGE.md` | the three headings, with the pushed image's digest | **5** — one of the digest, the base image or the seven versions missing |
| 10 | `TROUBLESHOOTING.md` | all four, with evidence | **5** — two or three |

Nothing is graded on the biology, and your records do not have to match last week's.

## What this costs in wall clock

- Building on your laptop: about a minute and a half.
- Pushing: five to twenty minutes on home internet.
- The pull job: about three minutes.
- The array and the cohort job: the same as last week, about 20 minutes once they start, plus any
  wait in the queue.
- Breakage 1: two builds, a day apart.
