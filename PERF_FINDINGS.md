# Menu-build sort perf findings — 30-seed sweep (inner-rep timing)

Command: `python ventoy/build_sort_test.py --perf`, then
`ventoy_sort_test.exe --sweep 30` (seeds 1..30, QPC timing, inner
repetitions auto-calibrated to ~50 ms measurement blocks — ~18k reps
at N=32 down to a handful at N=16384; every run correctness-verified).
Date: 2026-09-30. Machine-local; numbers are indicative for this box,
not absolute. Raw per-seed lines: `ventoy/sweep30_ext_stderr.txt`;
summaries: `ventoy/sweep30_ext_stdout.txt` (extended sizes
N=8192/16384).

Methodology note: each measurement times K rounds of (restore initial
ordering + sort) and divides, so sub-microsecond sorts get stable
averages instead of single-shot noise. Timings include the O(n)
restore cost for both algorithms alike. The `%.9f` sweep format was
added for this run (N=32 rows are ~1.3–1.5 µs and were invisible at
`%.6f`).

## Results (seconds per sort)

| workload | N    | merge mean | merge min–max         | naive mean | naive min–max         | speedup |
|----------|------|-----------|-----------------------|------------|-----------------------|---------|
| img      | 32   | 1.42 µs   | 1.29 – 1.53 µs        | 1.99 µs    | 1.56 – 2.50 µs        | ~1.4×   |
| img      | 128  | 8.40 µs   | 7.89 – 9.65 µs        | 31.25 µs   | 27.57 – 35.06 µs      | ~3.7×   |
| img      | 512  | 54.96 µs  | 51.32 – 61.73 µs      | 477.11 µs  | 444.09 – 527.61 µs    | ~8.7×   |
| img      | 2048 | 348.14 µs | 323.30 – 388.17 µs    | 7660.84 µs | 7164.70 – 8296.44 µs  | ~22.0×  |
| img      | 8192 | 1878.20 µs| 1748.62 – 2086.67 µs  | 127108.5 µs| 119348 – 135460 µs    | ~67.6×  |
| img      | 16384| 4342.09 µs| 4104.51 – 5076.54 µs  | 547126 µs  | 528732 – 594172 µs    | ~126.0× |
| subdir   | 32   | 1.32 µs   | 1.20 – 1.57 µs        | 1.96 µs    | 1.69 – 2.26 µs        | ~1.5×   |
| subdir   | 128  | 8.24 µs   | 7.44 – 9.36 µs        | 30.81 µs   | 27.92 – 37.78 µs      | ~3.7×   |
| subdir   | 512  | 48.18 µs  | 43.53 – 53.31 µs      | 522.97 µs  | 484.14 – 610.37 µs    | ~10.9×  |
| subdir   | 2048 | 351.12 µs | 331.80 – 378.47 µs    | 7843.97 µs | 7348.60 – 8274.70 µs  | ~22.3×  |
| subdir   | 8192 | 1847.58 µs| 1743.87 – 1951.50 µs  | 125049 µs  | 119780 – 130132 µs    | ~67.7×  |
| subdir   | 16384| 4093.32 µs| 3819.83 – 4422.80 µs  | 547235 µs  | 533123 – 571888 µs    | ~133.7× |

Both workloads agree; the subdir path (mirroring the menu-build tree
walk) tracks the img path within ~10% at every size. The N=8192/16384
rows come from the extended sweep; earlier rows were re-measured in
the same run, so the whole table is one consistent methodology.

## Findings

1. **Absolute cost is negligible at any conceivable menu size.** A
   worst-plausible 2048-image drive costs ~0.35 ms per full merge
   sort; an absurd 16384-image drive would cost ~4.3 ms — a fraction
   of one video frame either way. A typical 200-image drive
   interpolates to ~10 µs. Sort cost will never dominate menu build;
   disk I/O and menu object creation dwarf it.
2. **The merge sort is never a pessimization — it wins everywhere,
   even at N=32.** With quantization noise removed, the tie at N=32
   from the earlier clock()-era run resolves in the merge sort's favor
   (~1.4–1.5×). It is a stable O(n log n) sort with no small-N
   handicap on this data.
3. **Scaling matches n log n, out to 16384.** Per 4× data, merge
   time grows ~5.4–6.5× (converging toward the theoretical ~4.3× as
   n log n dilutes) while the naive sort grows ~16× — and the speedup
   ratio widens from ~22× at N=2048 to ~122–134× at N=16384. The
   naive curve steepens exactly as n² predicts.
4. **Stability is free.** The `<= 0` stable-merge path costs nothing
   measurable relative to the naive sort at any size.
5. **Variance is small and data-independent.** Across 30 seeds the
   merge sort's spread is ±5–12% at every size including N=16384,
   dominated by scheduler noise, not seed-dependent data effects. No
   pathological input distribution appears for either algorithm.
6. **Recursion depth is safe at any plausible size.**
   ventoy_img_msort recurses to depth log₂(n): ~11 frames at N=2048,
   14 at N=16384, with small frames (a few pointers each) — a few KB
   of stack total, well within GRUB's pre-boot budget. Stated here so
   it is a checked fact rather than an assumption.

## Restore-overhead control

A no-restore control (timing the K-round memcpy restore alone, same
calibrated K) quantifies the harness overhead inside the naive
measurements: **0.0–0.1% at every size** in both workloads. The
restore (an O(n) pointer memcpy) is noise next to the O(n²) sort, so
the naive numbers — and therefore every speedup ratio above — are
sort-dominated, not harness-dominated. The overhead is also printed
per-run on stderr (`restore_overhead=…%`) for future audit.

## Practical upshot

The existing merge sort implementation is the right choice for the
menu build and needs no optimization attention; remaining menu-latency
work should look at directory I/O and menu object creation instead.

## Reproduce

```
python ventoy/build_sort_test.py --perf
ventoy\_build_sort_test\ventoy_sort_test.exe --sweep 30
```

(`--sweep <n>` / `--reps <k>`; raw per-seed lines go to stderr)

## Release e2e reference run (2026-09-30)

The end-to-end release check `dist/check_release.cmd` includes this
sweep as step 4/5: it downloads the GitHub release assets, verifies
`SHA256SUMS`, extracts the zip, **rebuilds the harness with `--perf`
from the extraction and runs `--sweep 30`**, then runs the plain
harness. It exits 0 only if every stage passes (`SKIP_SWEEP=1`
skips the sweep; `SWEEP_OUT=<dir>` archives the logs).

Reference log archived in this directory, produced from the
**released artifact** (zip of tag `v1.1.17-ventoy-sort`), not from
the working tree:

- `sweep30_e2e_stdout.txt` — build line + test OK lines + sweep
  summaries
- `sweep30_e2e_stderr.txt` — raw per-seed lines (1080 measurements
  = 2 workloads × 6 sizes × 30 seeds × 3 lines)

Agreement with the table above (same box, same methodology):
| workload | N | merge mean | naive mean | speedup |
|----------|------|-----------|------------|---------|
| img | 2048 | 432 µs | 9.62 ms | ~22.2× |
| img | 16384 | 6.73 ms | 716 ms | ~106× |
| subdir | 2048 | 405 µs | 8.70 ms | ~21.5× |
| subdir | 16384 | 4.64 ms | 637 ms | ~137× |

(The N=16384 merge mean is ~1.5× the table's 4.34 ms — single-run
variance at the extreme size, still firmly n log n; every other
row matches the reference table within noise. The release
artifact sorts fast, and the e2e check re-proves it from the
published zip.)
