# Week 3 — four deliberate failures (container)

## 1. Unpinned rebuild: `FROM ubuntu` with no tag

In a scratch folder outside the repository, `~/w3-break1`, a Dockerfile with nothing pinned:

```
FROM ubuntu
RUN apt-get update && apt-get install -y curl
```

First build, earlier on 2 October:

```
$ docker build --platform linux/amd64 -t break1:day1 .
 => [1/2] FROM docker.io/library/ubuntu:latest@sha256:3595d7fc4286a33fad0…
$ docker run --rm --platform linux/amd64 break1:day1 dpkg -l > day1.txt
```

Second build, with both flags so nothing came from the cache, at 12:39 EDT the same day:

```
$ docker build --platform linux/amd64 --pull --no-cache -t break1:day2 .
#5 [1/2] FROM docker.io/library/ubuntu:latest@sha256:3595d7fc4286a33fad0fd853a4063e654287a9c3787437d7937c94ca3f7a804e
$ docker run --rm --platform linux/amd64 break1:day2 dpkg -l > day2.txt
$ wc -l day1.txt day2.txt
     122 day1.txt
     122 day2.txt
$ diff day1.txt day2.txt
$
```

**I aimed at** two different package lists and **got** two identical ones: no line
differs. The reason is that I had to run both builds on the same day, a few hours
apart, rather than a day apart. `--pull` really did ask Docker Hub again, but
`ubuntu:latest` still pointed at the same image (`sha256:3595d7fc…804e` both times),
and the Ubuntu archive had published no new versions of these 122 packages in
between. Nothing in this recipe *stops* them from changing: on another day `latest`
moves to a new image and `apt-get install` resolves whatever versions are current,
so the same Dockerfile silently builds different software.

**Fix:** pin everything, as `containers/Dockerfile` does: a tagged base image
(`mambaorg/micromamba:2.0.5-ubuntu24.04`, recorded by digest in `IMAGE.md`) and an
`=version` on every tool, so a rebuild resolves to the same versions.

## 2. No `--bind`

I made a copy of `01_persample.sbatch` without the `--bind` line and ran one sample:

```
$ sed '/--bind/d' 01_persample.sbatch > break_nobind.sbatch
$ sbatch --array=1 --export=NONE,RUN_ROOT=/scratch/$USER/w3-break2 break_nobind.sbatch
$ sacct -j 10761215 --format=JobID,State,Elapsed,ExitCode
10761215_1       FAILED   00:00:05     65:0
$ tail logs/persample_10761215_1.out
task 1: NA12878 on c0642, 8 cores, image /scratch/loveman.e/containers/variant-call.sif
error: no samplesheet at /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

It stopped after 5 seconds with exit code 65, before stage 0 began. The path the
container could not see was `/courses/BINF6610.202710/data/samplesheet-variant8.csv`.
Outside the container the job script read that same file fine (it found `NA12878` on
row 1), but inside, without `--bind`, the container only sees my home directory,
`/tmp` and the submit folder, so `/courses` does not exist there. My pipeline checks
the samplesheet before anything else and stopped with an error rather than running
on nothing.

**Fix:** keep `--bind /courses/BINF6610.202710,/scratch/${USER}`, which adds the
course data and my run folder.

## 3. No `--env THREADS`

A copy of `01_persample.sbatch` without the `--env THREADS` line, one sample, with
the job still asking for 8 cores:

```
$ sed '/--env THREADS/d' 01_persample.sbatch > break_nothreads.sbatch
$ sbatch --array=1 --export=NONE,RUN_ROOT=/scratch/$USER/w3-break3 break_nothreads.sbatch
$ sacct -j 10761217 --format=JobID,State,Elapsed,ExitCode
10761217_1    COMPLETED   00:08:23      0:0
```

It finished with no error. Only the logs show what went wrong:

```
$ grep "CMD:" /scratch/$USER/w3-break3/logs/NA12878.bwa.log
[main] CMD: bwa mem -t 4 -R @RG\tID:NA12878\tSM:NA12878 …
$ grep -i thread /scratch/$USER/w3-break3/logs/NA12878.haplotypecaller.log
16:17:19.740 INFO  IntelPairHmm - Available threads: 8
16:17:19.740 INFO  IntelPairHmm - Requested threads: 4
```

The same sample in the real containerised run:

```
[main] CMD: bwa mem -t 8 -R @RG\tID:NA12878\tSM:NA12878 …
16:14:53.058 INFO  IntelPairHmm - Available threads: 8
16:14:53.058 INFO  IntelPairHmm - Requested threads: 8
```

I asked for **8 cores** and the pipeline used **4**: bwa ran with `-t 4`, and GATK
saw 8 threads available but was asked for 4. `--cleanenv` dropped the `THREADS` the
job script set, so `lib/common.sh` fell back to its default, `THREADS=${THREADS:-4}`.
Half the cores I reserved sat idle, and nothing failed.

**Fix:** keep `--env THREADS="${THREADS}"`, so the value from `SLURM_CPUS_PER_TASK`
reaches the tools inside the container.

## 4. An arm64 image on Explorer

On a compute node (`srun`), with the cache on `/scratch`:

```
$ apptainer pull --arch arm64 arm.sif docker://ubuntu:24.04
INFO:    Converting OCI blobs to SIF format
…
INFO:    Creating SIF file...
$ apptainer exec arm.sif uname -m
FATAL:   While checking container encryption: could not open image /scratch/loveman.e/arm.sif: the image's architecture (arm64) could not run on the host's (amd64)
srun: error: c0638: task 0: Exited with exit code 255
```

**The pull succeeded**: Apptainer downloaded and converted the arm64 image without
any warning. **The run failed** at once, because Explorer's CPUs are amd64 and cannot
execute arm64 programs. A wrong-architecture image only reveals itself when you try
to run it.

**Fix:** build with `--platform linux/amd64` and check before pushing:
`docker image inspect --format '{{.Architecture}}' eloveman1/variant-call:1.0`
printed `amd64` for my image.

## Also: a real failure, not on purpose — micromamba under emulation

My first `docker build --platform linux/amd64` of `containers/Dockerfile` on my
Apple Silicon laptop failed in under a second:

```
0.783 Unexpected error 9 on netlink descriptor 16.
bash: line 1:     7 Aborted                 micromamba install --yes --name base …
ERROR: failed to build: … exit code: 134
```

The Dockerfile was fine. Building an amd64 image on an arm64 Mac means Docker
emulates an Intel CPU, and its default emulator (QEMU) does not support a network
call micromamba makes when it starts, so micromamba aborted before downloading
anything. **Fix:** Docker Desktop → Settings → General → *Use Rosetta for
x86_64/amd64 emulation on Apple Silicon*, then rebuild. The micromamba step then
ran in 38 seconds, and the image reported `amd64`.

## Use of AI (week 3)

I used Claude (Anthropic) to write `containers/Dockerfile`, `slurm/pull.sbatch`, the
`apptainer exec` changes to both job scripts and `IMAGE.md`, to explain each part,
and to diagnose the micromamba build error. I built and pushed the image, ran the
cohort and all four breakages myself, and every command and output above is from
my own laptop and my own Explorer jobs.
