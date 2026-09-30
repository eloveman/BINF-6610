# Resources

Fill every ___ with numbers from your own jobs, and paste the real output.

## Per-sample job (01_persample.sbatch)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| First asked for | 8 | 16G | 01:00:00 |
| Measured | ___ cores busy (CPU Utilized / wall) | peak ___ GB (memory.peak) | slowest task ___ |
| Set to | ___ | ___ | ___ |

### Core-count comparison (same sample, only -c changed)

| -c | wall clock | core-minutes (c × minutes) |
|---|---|---|
| 4 | ___ | ___ |
| 8 | ___ | ___ |
| 16 | ___ | ___ |

```
paste: sacct -j <id4>,<id8>,<id16> --format=JobID,State,Elapsed,MaxRSS,AllocCPUS
```

```
paste: seff <one per-sample job id>
```

**Decision:** I set --cpus-per-task to ___ because ___ (e.g. going from ___ to ___
cores cut the time by only ___ while costing ___ more core-minutes). I set --mem
to ___ because the measured peak was ___ GB (memory.peak, not MaxRSS, because ___).
I set --time to ___ because the slowest task took ___.

## Cohort job (02_cohort.sbatch)

| | --cpus-per-task | --mem | --time |
|---|---|---|---|
| First asked for | 2 | 8G | 01:00:00 |
| Measured | ___ | ___ | ___ |
| Set to | ___ | ___ | ___ |

```
paste: seff <cohort job id>
```

**Decision:** ___
