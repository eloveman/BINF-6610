<!-- Paste this at the END of your existing TROUBLESHOOTING.md, fill it in, then delete this file. -->

# Week 2 — four deliberate failures

## 1. --time=00:02:00

```
paste: sacct -j <id> --format=JobID,State,Elapsed,ExitCode
```
State: ___. The log stopped at: ___ (last line of logs/persample_<id>_1.out).
Left on disk under $RUN_ROOT: ___ (e.g. a trimmed FASTQ but no BAM).

## 2. One task exits 1, cohort job on afterok

```
paste: sacct -j <array id>,<cohort id> --format=JobID,JobName,State,ExitCode,Reason
```
The task ___. The cohort job was ___ with Reason ___, because afterok requires
every task to succeed and --kill-on-invalid-dep cancels a dependency that can
no longer be met.

## 3. --array=1-9 against the eight-row samplesheet

```
paste: sacct -j <id> --format=JobID,State,ExitCode
paste: the line from logs/persample_<id>_9.out
```
Task 9 got an empty sample name and ___. Without the guard, ___ (hint: what does
rows() print when SAMPLE is empty? and what does run_sample.sh's ${3:?} do?).

## 4. scancel mid-write, then resubmit

```
paste: sacct for the cancelled job and for the rerun
```
Cancelled during stage ___. Left behind: ___ (ls -la of the stage's folder).
The rerun ___ trust it: ___ (e.g. every stage rewrites its outputs; the GVCF
is written as *.partial.g.vcf.gz and renamed only when complete).
