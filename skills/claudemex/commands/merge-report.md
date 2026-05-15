---
name: merge-report
description: Re-print merge-report.md and drift-report.md from an existing merged/<YYYY-WW>/ directory without re-running the merge algorithm.
---

# /merge-report — re-print merge / drift reports

Activates `claudemex merge-report`. Useful for revisiting reports days
after the merge or piping into a viewer.

## Usage

```
/merge-report                                # current ISO week, full reprint
/merge-report --week=2026-W18                # explicit week
/merge-report --dir=merged/special           # explicit dir (overrides --week)
/merge-report --diff-only                    # skip merge summary, drift only
```

The drift report contains:
- **Summary** table — one row per drift section (`MINORITY` / `NO-CONSENSUS`)
- **Details** section — per-host short hash + line count + `majority` marker

See `docs/merge-guide.md` for how to read the drift report.
