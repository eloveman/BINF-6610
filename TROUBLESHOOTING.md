# Troubleshooting — Week 4 (Nextflow)

Four failures caused on purpose. Last week's four are in the Git history.

## 1. Ctrl-C halfway through a smoke run, then -resume

**Command.** A fresh smoke run on the laptop, stopped with Ctrl-C as soon as
HaplotypeCaller started:

    nextflow run main.nf -profile docker \
        --samplesheet ~/binf6610/smoke-data/smoke/samplesheet.csv \
        --ref ~/binf6610/smoke-data/smoke/smoke.fa \
        --region smoke_1mb -ansi-log false

then the same command with `-resume`.

**What it printed.** The interrupted run had submitted 15 tasks; the last was
`[98/0dcb4d] Submitted process > HAPLOTYPECALLER (smoke_03)`. The -resume run:

    [ae/dd0440] Cached process > VALIDATE
    [23/e11897] Cached process > FASTQC (smoke_03)
    [d7/faa9c4] Cached process > FASTQC (smoke_02)
    [95/569df4] Cached process > FASTQC (smoke_01)
    [5f/de86ae] Cached process > FASTP (smoke_01)
    [ca/e5a7cb] Cached process > FASTP (smoke_02)
    [26/08f2c7] Cached process > FASTP (smoke_03)
    [17/f53fe7] Cached process > BWA_MEM (smoke_01)
    [fb/90b0ae] Cached process > BWA_MEM (smoke_03)
    [98/2083a3] Cached process > BWA_MEM (smoke_02)
    [3c/fd4059] Cached process > MARKDUPLICATES (smoke_03)
    [30/177dcd] Submitted process > MULTIQC
    [05/fec027] Submitted process > MARKDUPLICATES (smoke_01)
    [93/667640] Submitted process > MARKDUPLICATES (smoke_02)
    [4a/1be7e0] Submitted process > HAPLOTYPECALLER (smoke_03)
    [93/3bdfa0] Submitted process > HAPLOTYPECALLER (smoke_02)
    [7d/e40be0] Submitted process > HAPLOTYPECALLER (smoke_01)
    [b1/89c8a3] Submitted process > JOINT_GENOTYPE
    [f0/55067f] Submitted process > FILTER
    [02/9eb2aa] Submitted process > PUBLISH

**Which were cached and which ran again.** Cached: the 11 tasks that had
finished before Ctrl-C — VALIDATE, FASTQC x3, FASTP x3, BWA_MEM x3 and
MARKDUPLICATES (smoke_03). They kept their task hashes (VALIDATE is
`ae/dd0440` in both runs). Ran again: the 4 tasks that were still running
when I pressed Ctrl-C — MULTIQC, MARKDUPLICATES (smoke_01, smoke_02) and
HAPLOTYPECALLER (smoke_03) — each in a new work folder (MULTIQC 3f/e83059 ->
30/177dcd, HAPLOTYPECALLER smoke_03 98/0dcb4d -> 4a/1be7e0), plus the 5
that had not started.

**Fix.** Nothing to fix: -resume reused every finished task and reran only
what had not finished. A task counts as finished only when it exits 0, so
an interrupted task is never mistaken for a complete one.

## 2. The reference given to BWA_MEM as a queue channel

**Command.** In `main.nf`, stage 3's call only, changed `ref` to a queue channel:

    BWA_MEM(FASTP.out.reads, channel.fromPath(params.ref), ref_index)

and ran the smoke dataset:

    nextflow run main.nf -profile docker \
        --samplesheet ~/binf6610/smoke-data/smoke/samplesheet.csv \
        --ref ~/binf6610/smoke-data/smoke/smoke.fa \
        --region smoke_1mb --outdir results-failure2 -resume

**What it printed.**

    [26/08f2c7] FASTP (smoke_03)           | 3 of 3, cached: 3 ✔
    [98/2083a3] BWA_MEM (smoke_02)         | 1 of 1, cached: 1 ✔
    [93/667640] MARKDUPLICATES (smoke_02)  | 1 of 1, cached: 1 ✔
    [93/3bdfa0] HAPLOTYPECALLER (smoke_02) | 1 of 1, cached: 1 ✔
    [9f/b38de9] JOINT_GENOTYPE             | 1 of 1 ✔
    [07/93d8b4] FILTER                     | 1 of 1 ✔

and the VCF's header line had one sample column:

    #CHROM POS ID REF ALT QUAL FILTER INFO FORMAT smoke_02

**How many samples BWA_MEM ran, and what stopped the run.** BWA_MEM ran one
sample of three, smoke_02. Nothing stopped the run: every line ended in ✔
and it published a VCF with one sample. `channel.fromPath` made the
reference a queue channel with one item, and the first sample to reach
BWA_MEM used it up, so smoke_01 and smoke_03 never ran. The only sign was
`1 of 1` where FASTP said `3 of 3`.

**Fix.** Put back `BWA_MEM(FASTP.out.reads, ref, ref_index)`, where
`ref = file(params.ref)` is a value channel that every sample reads
(`git checkout main.nf`).

## 3. A missing backslash before $( in a script block

**Command.** My FASTP and BWA_MEM have no `\$(…)`, so I added one line to
FASTQC's script block, with the backslash taken off its `$`. The correct
line would be:

    echo "${meta.id}: \$(ls ${reads} | wc -l) FASTQ file(s)" >&2

I wrote it as `$(ls ${reads} | wc -l)` and ran the smoke dataset:

    nextflow run main.nf -profile docker \
        --samplesheet ~/binf6610/smoke-data/smoke/samplesheet.csv \
        --ref ~/binf6610/smoke-data/smoke/smoke.fa \
        --region smoke_1mb --outdir results-failure3 -resume -ansi-log false

**What it printed.** Nothing failed. The three FASTQC tasks ran
(`[37/5e0932] Submitted process > FASTQC (smoke_01)`) and the run finished.
In smoke_01's work folder, work/37/5e0932…:

    $ cat .command.sh
    #!/bin/bash -euo pipefail
    fastqc -q -t 1 smoke_01_R1.fastq.gz smoke_01_R2.fastq.gz > smoke_01.fastqc.log 2>&1
    echo "smoke_01: smoke_01_R1.fastq.gz smoke_01_R2.fastq.gzls  | wc -l) FASTQ file(s)" >&2

    $ cat .command.err
    smoke_01: smoke_01_R1.fastq.gz smoke_01_R2.fastq.gzls  | wc -l) FASTQ file(s)

    $ bash .command.run
    smoke_01: smoke_01_R1.fastq.gz smoke_01_R2.fastq.gzls  | wc -l) FASTQ file(s)

**What happened.** I aimed at a failed task and got a task that succeeded
and printed the wrong thing. Nextflow read the unescaped `$(` itself, before
bash saw the script: .command.sh has no `$(` left, and the file names from
`${reads}` are pasted in front of `ls`. bash never ran a command
substitution; it ran echo on a scrambled string, which exits 0.
`bash .command.run` reran the task in its container and printed the same
line, because it runs the same .command.sh. Inside a real command, such as
`n=$(gzip -dc … | wc -l)`, this would give a wrong value with no error.

**Fix.** Write `\$` for every `$` that bash should see:
`\$(ls ${reads} | wc -l)`. (Restored with `git checkout modules/fastqc.nf`.)

## 4. A two-minute time limit for HaplotypeCaller on Explorer

**Command.** Before the first Explorer run, inside the explorer profile's
`process` block in nextflow.config:

    withName: 'HAPLOTYPECALLER' {
        time = '2m'
    }

then `sbatch slurm/nextflow.sbatch` (head job 10951079).

**What it printed.** In nf-head-10951079.out, once HaplotypeCaller started:

    ERROR ~ Error executing process > 'HAPLOTYPECALLER (NA12892)'

    Caused by:
      Process `HAPLOTYPECALLER (NA12892)` terminated with an error exit status (140)
    ...
    WARN: Killing running tasks (7)

and in sacct:

    JobID                                    JobName      State    Elapsed  Timelimit ExitCode
    10951469            nf-HAPLOTYPECALLER_(NA12003) CANCELLED+   00:01:12   00:02:00      0:0
    10951470            nf-HAPLOTYPECALLER_(NA12892)     FAILED   00:01:12   00:02:00     12:0
    10951509            nf-HAPLOTYPECALLER_(NA07357) CANCELLED+   00:00:33   00:02:00      0:0
    10951511            nf-HAPLOTYPECALLER_(NA12873) CANCELLED+   00:00:33   00:02:00      0:0
    10951512            nf-HAPLOTYPECALLER_(NA12878) CANCELLED+   00:00:32   00:02:00      0:0
    10951513            nf-HAPLOTYPECALLER_(NA10851) CANCELLED+   00:00:30   00:02:00      0:0
    10951514            nf-HAPLOTYPECALLER_(NA12891) CANCELLED+   00:00:30   00:02:00      0:0

**What happened.** Exit status 140, not TIMEOUT. Every task's job has
`#SBATCH --signal B:USR2@30`: Slurm warns the job with USR2 before its time
limit, and Nextflow stops the task when the warning comes. USR2 is signal
12, and a process stopped by a signal exits 128 + 12 = 140. sacct records
the job as FAILED after 1 min 12 s of its 2 min Timelimit, never TIMEOUT.
GATK's progress log stopped at chr20:2262585, 1.0 minutes into a 10 Mb
region. Nextflow then cancelled the six other HaplotypeCaller jobs
(CANCELLED+).

**Fix.** Removed the two-minute block, so HaplotypeCaller is back to the
`1h` of the `BWA_MEM|HAPLOTYPECALLER` block, and resubmitted (head job
10951646). -resume reused every task that had finished, and the run carried
on from HaplotypeCaller: cpus, memory and time are not part of the task
hash, so the finished tasks were not rerun.
