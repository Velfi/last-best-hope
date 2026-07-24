# Close Engagement visual cost — 2026-07-23

## Result

The current close-engagement renderer is comfortably inside its 8 ms CPU p95
budget at 1280×720. Five sequential matched runs of the normal and 1,000-ship
stress scenarios all passed.

| Scenario | Median of run medians | Median of run p95s | Worst run p95 | Worst sample | Worst-p95 headroom |
| --- | ---: | ---: | ---: | ---: | ---: |
| Normal combat | 0.3013 ms | 0.3235 ms | 2.0044 ms | 2.0543 ms | 75.0% |
| 1,000-ship stress | 0.3551 ms | 0.3801 ms | 1.8412 ms | 2.3518 ms | 77.0% |

The median paired p95 increase from normal combat to the 1,000-ship stress
case was 0.0668 ms. Both scenarios remained at 99 draw calls and 99 batches,
so the stress formation remains batched rather than scaling submission count
with ship count.

Two of the five runs were globally slower in both scenarios. Those runs are
retained: the normal p95 range was 0.3018–2.0044 ms and the stress p95 range
was 0.3686–1.8412 ms. The correlated shift suggests system-level variability,
but this profile does not assign a cause without a targeted trace.

## Debris-field structural delta

At the time of this capture, relative to the prior ring-and-scratch
construction, the plate construction added 24 line instances:

- Prior: 116 volume lines + 28 scratches = 144 instances.
- Current: 96 base lines + 24 plates × 3 detail lines = 168 instances.
- Delta: +24 instances, +1,344 bytes of persistently mapped instance data per
  frame, and +144 generated vertices / +48 triangles.
- Draw-call delta: zero; all world lines remain one instanced draw.

This historical calculation predates the subsequent filled-wreck pass and is
not a current geometry count. It is a structural workload calculation, not a
before/after timing claim.
The debris shader also performs additional fragment work, but GPU frame timing
is unavailable on this Apple/MoltenVK device
(`timestampComputeAndGraphics=false`), so its time cost is not quantified here.
The benchmark's `upload_bytes=0` counter does not include the renderer's direct
copies into persistently mapped Vulkan buffers.

## Runs

Each result contains 180 measured samples with seed `24301`.

| Run | Normal median | Normal p95 | Normal max | Stress median | Stress p95 | Stress max |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0.2761 | 0.3018 | 0.3362 | 0.3533 | 0.3686 | 0.3751 |
| 2 | 0.8740 | 1.7729 | 2.0543 | 1.0695 | 1.8412 | 2.3518 |
| 3 | 0.3013 | 0.3235 | 0.8112 | 0.3375 | 0.3711 | 0.6269 |
| 4 | 0.8867 | 2.0044 | 2.0506 | 1.0306 | 1.7864 | 2.1238 |
| 5 | 0.2915 | 0.3123 | 0.3208 | 0.3551 | 0.3801 | 0.3969 |

All times are milliseconds.

## Reproduction

```sh
VIZZA_GPU_PROFILER=1 build/last-best-hope --benchmark-combat-render 180 24301
```

Raw outputs:

- `/tmp/lbh-combat-visual-cost-run1.jsonl`
- `/tmp/lbh-combat-visual-cost-run2.jsonl`
- `/tmp/lbh-combat-visual-cost-run3.jsonl`
- `/tmp/lbh-combat-visual-cost-run4.jsonl`
- `/tmp/lbh-combat-visual-cost-run5.jsonl`

This is a working-tree characterization, not an accepted before/after
baseline. This checkout has no Git metadata, so the exact revision and
cleanliness cannot be recorded and no causal performance delta is claimed.
