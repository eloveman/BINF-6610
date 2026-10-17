# Troubleshooting — week 5, Snakemake

Four failures caused on purpose, each with the command, what it printed, and the fix.

## 1 · A run stopped halfway with Ctrl-C

**Command.** On the laptop, from an empty `results/`, `work/` and `logs/`:

    snakemake --profile profiles/laptop \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

stopped with Ctrl-C after `validate` had finished, while `fastqc` was running on `smoke_03`.
Then the same command again.

**What it printed.** The rerun refused to start:

    IncompleteFilesException:
    The files below seem to be incomplete. If you are sure that certain files are not incomplete, mark them as complete with

        snakemake --cleanup-metadata <filenames>

    To re-generate the files rerun your command with the --rerun-incomplete flag.
    Incomplete files:
    work/fastqc/smoke_03

Snakemake records which outputs a running job has started; Ctrl-C killed the job before it
finished, so `work/fastqc/smoke_03` was marked as possibly cut off.

**Fix.** The option it named, `--rerun-incomplete`:

    snakemake --profile profiles/laptop --rerun-incomplete \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

It ran 20 of the 21 jobs: `validate` had finished before the Ctrl-C and was reused, and
`fastqc` on `smoke_03` was run again from scratch (`reason: Forced execution`). The run
finished in 54 s, and its `results/` is the copy in `smoke-run-smk/`.

## 2 · A log without the output's wildcard

**Command.** In the Snakefile, `bwa_mem`'s `log:` changed from `"logs/bwa_mem/{sample}.log"`
to `"logs/bwa_mem.log"`, then:

    snakemake --profile profiles/laptop -n \
        --config samplesheet=$HOME/smoke/samplesheet.csv ref=$HOME/smoke/smoke.fa region=smoke_1mb

**What it printed.** Snakemake refused while reading the Snakefile, before building any jobs:

    RuleException in file "/Users/elyseloveman/binf6610/Snakefile", line 141:
    Not all output, log and benchmark files of rule bwa_mem contain the same wildcards. This is crucial though, in order to avoid that two or more jobs write to the same file.

**Why.** `bwa_mem` runs once per sample, and its output has `{sample}`. A log without
`{sample}` is one file for all three jobs, so jobs running in parallel would write over each
other's logs. Snakemake checks this when it reads the rule, not when the jobs run.

**Fix.** Put `{sample}` back: `"logs/bwa_mem/{sample}.log"`.

## 3 · The two fastp rules without wildcard_constraints

**Command.** Both `wildcard_constraints:` blocks deleted from `fastp_paired` and
`fastp_single`, then the same dry run.

**What it printed.**

    AmbiguousRuleException:
    Rules fastp_single and fastp_paired are ambiguous for the file work/trim/smoke_01_R1.trim.fastq.gz.
    Consider starting rule output with a unique prefix, constrain your wildcards, or use the ruleorder directive.
    Wildcards:
        fastp_single: sample=smoke_01
        fastp_paired: sample=smoke_01

**Why.** The two rules have the same output names on purpose, so that `bwa_mem` can ask for
`work/trim/{sample}_R1.trim.fastq.gz` without knowing a sample's library type. Without the
constraints, both rules can make that file for any sample, and Snakemake will not pick one.
It named the first trimmed file it needed, `smoke_01`'s R1.

**Fix.** Put the constraints back: `sample=one_of(PAIRED)` on `fastp_paired` and
`sample=one_of(SINGLE)` on `fastp_single`, so each sample matches exactly one rule.

## 4 · The first Explorer run without Apptainer

**Command.** `software-deployment-method: apptainer` deleted from
`profiles/explorer/profile.yaml`, then `sbatch slurm/snakemake.sbatch` (head job 11138220).

**What it printed.** The head job's log said only that Slurm jobs had failed:

    Error in rule fastp_paired:
        message: SLURM-job '11138264' failed, SLURM status is: 'FAILED'. Reason: Unknown.

The first rule to fail was `fastp_paired`, on NA12878. The other `fastp_paired`,
`fastp_single` and `fastqc` jobs failed the same way. That job's own Slurm log,
`.snakemake/slurm_logs/rule_fastp_paired/NA12878/11138264.log`, gives the exit status:

    Command 'set -euo pipefail;  (fastp -w 4 -i ... ) 2> logs/fastp/NA12878.log' returned non-zero exit status 127.

and the rule's own log, `logs/fastp/NA12878.log`, says why:

    /usr/bin/bash: line 1: fastp: command not found

`logs/fastqc/NA12878.log` says the same for `fastqc`. Exit status 127 is the shell's code
for "command not found". `sacct` reports these jobs as `1:0`, not 127, because the Slurm
job is a Snakemake process wrapping the command, and it exits with 1 whenever its rule
fails. Only the job's own log has the 127.

**Why.** Without Apptainer each rule runs directly on a compute node, and the course
environment the head job activates has Snakemake but not the bioinformatics tools. So
every rule that calls a tool fails. `validate` succeeded, because
`validate_samplesheet.sh` only needs `awk` and `gzip`, which every node has.

**Fix.** Put the line back (`git checkout profiles/explorer/profile.yaml`) and submit the
same head job again. `snakemake -n` first showed that `validate`, although it had finished,
would run again:

    reason: Software environment definition has changed since last execution

The first run had used no image for `validate`, and this one uses the `tools` image, so
Snakemake reruns it. All 46 jobs ran in the second head job, 11138471.
