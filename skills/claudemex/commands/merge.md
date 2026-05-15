---
name: merge
description: Combine per-machine ClaudeMeX outputs into a common-kernel + per-machine extension via section-level majority vote. Run on any one machine after all hosts have generated outputs/.
---

# /merge — multi-machine ClaudeMeX merge

Activates `claudemex merge`. Reads `./outputs/<host>-<ts>/` directories,
votes section by section (default `K = max(2, ⌈N/2⌉)`), and writes
`merged/<YYYY-WW>/{common-kernel/, per-machine-extension/<host>/,
merge-report.md, drift-report.md}`.

## Usage

```
/merge                                    # current ISO week, default K
/merge --week=2026-W18                    # explicit week
/merge --threshold=2                      # explicit K (must be >= 2)
/merge --hosts=tk-mbp16-m3,h2ejvun        # explicit trusted-host whitelist
/merge --allow-untrusted-hosts            # opt out (NOT recommended)
```

## Trusted-host whitelist (REQUIRED)

Multi-machine merge refuses to run unless you have declared which hostnames
are real machines you control. Pick **one**:

1. `--hosts=h1,h2` per-run flag
2. `~/.config/claudemex/trusted-hosts` file (one host per line; lives
   outside the Syncthing-shared tree by design)
3. `--allow-untrusted-hosts` opt-out (only for fully-controlled `--from`)

See `docs/merge-guide.md` for the full guide.
