# Week 2 — four deliberate failures

Each was a separate submission of `slurm/01_persample.sbatch` (and, for
failure 2, `02_cohort.sbatch`), writing to its own `RUN_ROOT` under
`/scratch/loveman.e/` so that none of them could touch the real run.

## 1. `--time=00:02:00`

```
$ sbatch --time=00:02:00 --array=1 --export=NONE,RUN_ROOT=/scratch/$USER/break1 01_persample.sbatch
$ sacct -j 10717887 --format=JobID,State,Elapsed,ExitCode
JobID             State    Elapsed ExitCode
------------ ---------- ---------- --------
10717887_1      TIMEOUT   00:02:16      0:0
10717887_1.+  CANCELLED   00:02:19     0:15
```

The log stopped in stage 3, partway through alignment:

```
[18:58:41] NA12878: trimmed to 1222355 reads
[18:58:41] ===== stage 3 : align =====
slurmstepd: error: *** JOB 10717887 ON c0648 CANCELLED AT 2026-09-30T18:59:55 DUE TO TIME LIMIT ***
```

Left on disk: the FastQC reports, both trimmed FASTQs, and an `align/NA12878.raw.bam`
that bwa was still writing when Slurm killed it, so it is incomplete even though it
looks like a normal file. There is no sorted BAM and no GVCF. Slurm sends the job a
signal (exit 0:15, signal 15 = SIGTERM), so the pipeline never reaches its own checks,
and nothing marks that BAM as broken. A rerun is safe only because stage 3 rewrites
`raw.bam` from scratch rather than reusing it.

## 2. One task exits 1, with the cohort job on `afterok`

```
$ ARR=$(sbatch --parsable --array=2 --export=NONE,FAIL_TASK=2,RUN_ROOT=/scratch/$USER/break2 01_persample.sbatch)
$ sbatch --dependency=afterok:$ARR --kill-on-invalid-dep=yes --export=NONE,RUN_ROOT=/scratch/$USER/break2 02_cohort.sbatch
$ sacct -j 10717891,10717892 --format=JobID,JobName,State,ExitCode,Reason
JobID           JobName      State ExitCode                 Reason
------------ ---------- ---------- -------- ----------------------
10717891_2   vc-persam+     FAILED      1:0                   None
10717892      vc-cohort  CANCELLED      0:0             Dependency
```

`FAIL_TASK=2` makes task 2 exit 1 on purpose before it runs anything. The cohort job
was cancelled within seconds with Reason `Dependency` and never started. `afterok`
means "only if every task succeeded", so once one task failed the dependency could
never be met, and `--kill-on-invalid-dep=yes` cancelled the job instead of leaving
it pending. With `afterany` the cohort job would have started anyway and genotyped
whichever samples happened to have GVCFs.

## 3. Out-of-range task (`--array=9` against the eight-row samplesheet)

I submitted only task 9 rather than `--array=1-9`: tasks 1–8 would just have been
a second copy of the real run, and task 9 is the one being tested.

```
$ sbatch --array=9 --export=NONE,RUN_ROOT=/scratch/$USER/break3 01_persample.sbatch
$ sacct -j 10717888 --format=JobID,JobName,State,ExitCode
JobID           JobName      State ExitCode
------------ ---------- ---------- --------
10717888_9   vc-persam+     FAILED     64:0
$ cat logs/persample_10717888_9.out
task 9: no row 9 in /courses/BINF6610.202710/data/samplesheet-variant8.csv
```

The `awk 'NR == n + 1'` lookup found no row 10 in the file (header + 8 samples), so
`SAMPLE` was empty, and the guard `[[ -n "${SAMPLE}" ]] || … exit 64` stopped the task
before it ran anything.

Without that guard: `run_sample.sh` would have been called with an empty sample name.
Its `${3:?usage…}` would stop that too, as a second safety net. If both were missing,
`rows()` treats an empty `SAMPLE` as "every row", so task 9 would have run stages 0–5
on all eight samples, one after another, rewriting files the other eight tasks were
writing at the same time, and could still have finished COMPLETED.

## 4. `scancel` mid-write, then resubmit

I cancelled the job 20 seconds into stage 5, while HaplotypeCaller was writing the GVCF.
The folder already held a complete GVCF from an earlier test run at 19:21.

```
$ sacct -j 10726240 --format=JobID,State,Elapsed,ExitCode
JobID             State    Elapsed ExitCode
------------ ---------- ---------- --------
10726240_1   CANCELLED+   00:03:42      0:0

$ ls -la /scratch/$USER/break4/gvcf
-rw-r--r-- 1 loveman.e users 22698130 Sep 30 19:21 NA12878.g.vcf.gz
-rw-r--r-- 1 loveman.e users    10136 Sep 30 19:21 NA12878.g.vcf.gz.tbi
-rw-r--r-- 1 loveman.e users  4651338 Sep 30 22:29 NA12878.partial.g.vcf.gz
```

The cancel left a 4.6 MB `NA12878.partial.g.vcf.gz` with no index, but the finished
22.7 MB GVCF from 19:21 was untouched. Stage 5 writes to `*.partial.g.vcf.gz` and only
renames it to `*.g.vcf.gz` after checking it and its index exist, so a half-written
file never gets the name that stage 6 reads.

Then I resubmitted the same job:

```
$ sacct -j 10726279 --format=JobID,State,Elapsed,ExitCode
JobID             State    Elapsed ExitCode
------------ ---------- ---------- --------
10726279_1    COMPLETED   00:07:34      0:0

$ ls -la /scratch/$USER/break4/gvcf
-rw-r--r-- 1 loveman.e users 22698181 Sep 30 22:38 NA12878.g.vcf.gz
-rw-r--r-- 1 loveman.e users    10189 Sep 30 22:38 NA12878.g.vcf.gz.tbi
```

The rerun did not trust what was left behind. Every stage rewrites its outputs, and
stage 5 deletes any old `.partial` file before starting, so the leftover was removed
and a new complete GVCF written at 22:38.

## Use of AI (week 2)

I used Claude (Anthropic) to restructure my week-1 pipeline into `lib/common.sh`,
one file per stage, `run_sample.sh` and the four `slurm/` files, and to explain each
part. Claude also suggested the `FAIL_TASK` switch and the `.partial` file name for
the deliberate failures. I tested the restructured pipeline on the smoke dataset on
my laptop, ran the cohort and all four failures on Explorer myself, and took every
number and log line above from my own jobs.
