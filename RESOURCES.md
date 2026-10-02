# Resources

All numbers below are from my own jobs on Explorer (`courses` partition),
30 September 2026. Main run: array **10717844** (8 tasks), cohort job **10717845**.

## Per-sample job (`01_persample.sbatch`, stages 0–5)

| | `--cpus-per-task` | `--mem` | `--time` |
|---|---|---|---|
| First asked for | 8 | 16G | 01:00:00 |
| Measured | see core-count comparison below | program ≈ 6.2–6.9 GB; peaks up to 15.8 GB including file cache | 5:14 – 10:43 per task |
| Set to | **8** (unchanged) | **16G** (unchanged) | **00:30:00** (lowered) |

### Core-count comparison: NA12878, only `-c` changed

| `-c` | job | wall clock | core-minutes (c × minutes) |
|---|---|---|---|
| 4 | 10717885 | 8:37 | 34.5 |
| 8 | 10717844_1 | 7:10 | 57.3 |
| 16 | 10717886 | 6:44 | 107.7 |

```
$ sacct -j 10717885,10717886 --format=JobID,State,Elapsed,MaxRSS,AllocCPUS
JobID             State    Elapsed     MaxRSS  AllocCPUS
------------ ---------- ---------- ---------- ----------
10717885_1    COMPLETED   00:08:37                     4
10717885_1.+  COMPLETED   00:08:37   6261016K          4
10717886_1    COMPLETED   00:06:44                    16
10717886_1.+  COMPLETED   00:06:44  14248144K         16
```

### The main run: all eight tasks at 8 cores

```
$ sacct -j 10717844,10717845 --format=JobID,JobName,State,Elapsed,MaxRSS,AllocCPUS
JobID           JobName      State    Elapsed     MaxRSS  AllocCPUS
------------ ---------- ---------- ---------- ---------- ----------
10717844_1.+      batch  COMPLETED   00:07:10   6570376K          8
10717844_2.+      batch  COMPLETED   00:08:15  13139448K          8
10717844_3.+      batch  COMPLETED   00:06:17   6403804K          8
10717844_4.+      batch  COMPLETED   00:06:54   6567180K          8
10717844_5.+      batch  COMPLETED   00:05:14   6245720K          8
10717844_6.+      batch  COMPLETED   00:07:37   6612252K          8
10717844_7.+      batch  COMPLETED   00:10:43   6845484K          8
10717844_8.+      batch  COMPLETED   00:08:35  15157268K          8
10717845.ba+      batch  COMPLETED   00:07:07   1901408K          2
```

The kernel's memory high-water mark, printed by each job script from
`memory.peak` (bytes):

```
$ grep memory.peak logs/persample_10717844_*.out
logs/persample_10717844_1.out:memory.peak: 12909367296
logs/persample_10717844_2.out:memory.peak: 14753861632
logs/persample_10717844_3.out:memory.peak: 7184617472
logs/persample_10717844_4.out:memory.peak: 12814479360
logs/persample_10717844_5.out:memory.peak: 12520415232
logs/persample_10717844_6.out:memory.peak: 14805356544
logs/persample_10717844_8.out:memory.peak: 15804944384
```

(Task 7 was still running when I ran this, so its line is missing.)

### Decisions

**Cores: kept 8.** Going from 4 to 8 cores made the job only 17 % faster
(8:37 → 7:10) for 66 % more core-minutes, and going from 8 to 16 saved just
26 seconds while doubling the cost to 107.7 core-minutes. Most stages barely
use more than one or two cores; only alignment scales. 4 cores is the most
efficient, but 8 keeps the slowest sample, and so the whole cohort, a little
faster at a cost that is still reasonable. 16 is clearly past the point where
extra cores help.

**Memory: kept 16G.** The two measurements disagree. MaxRSS was about
6.2–6.9 GB for six of the eight tasks but 13.1 and 15.2 GB for the other two,
and `memory.peak` ranged from 7.2 to 15.8 GB, even for the same sample
(NA12878: 6.6 GB MaxRSS, 12.9 GB `memory.peak`). Both counters include file
cache, the ~9 GB reference and BWA index plus the FASTQs being read, which
the kernel fills up to whatever limit the job has. The lowest readings
(about 6.3–7.2 GB) are closest to what the programs actually need, which
matches the bwa index load. 16G is a bit over twice that real need, so I
kept it rather than risk a cluster that enforces the limit.

**Time: lowered 1:00:00 → 0:30:00.** The slowest of all eight tasks took
10:43 (task 7), so 30 minutes is almost three times the slowest
observed run and still frees the scheduler from a one-hour reservation.

## Cohort job (`02_cohort.sbatch`, stages 6–9)

| | `--cpus-per-task` | `--mem` | `--time` |
|---|---|---|---|
| First asked for | 2 | 8G | 01:00:00 |
| Measured | 2 allocated | MaxRSS 1.90 GB; `memory.peak` 1.95 GB | 7:07 |
| Set to | **2** (unchanged) | **4G** (lowered) | **00:30:00** (lowered) |

```
$ sacct -j 10717845 --format=JobID,State,Elapsed,MaxRSS
JobID             State    Elapsed     MaxRSS
------------ ---------- ---------- ----------
10717845      COMPLETED   00:07:07
10717845.ba+  COMPLETED   00:07:07   1901408K

$ tail -1 logs/cohort_10717845.out
memory.peak: 1948352512
```

**Decision:** here both measurements agree, at about 1.9 GB, because this job
reads small GVCFs rather than the whole reference. 8G was four times what it
used, so I lowered it to 4G, about twice the peak. 7:07 of a one-hour limit
was also far more than needed, so the limit is now 30 minutes. Cores stay at
2: the GATK steps here are mostly single-threaded.
