---
name: import
description: Extract one or more claudemex export tarballs into ./outputs/ on the merge node. Hardened against malicious tarballs (path traversal, symlinks, size bombs, setuid).
---

# /import — extract export tarballs onto the merge node

Activates `claudemex import`. Used as a transport fallback when Syncthing
or Gitea is unavailable.

## Usage

```
/import bundle.tar.gz                              # extract into ./outputs/
/import --into=/tmp/staging bundle.tar.gz          # custom target dir
/import --max-bytes=104857600 bundle.tar.gz        # custom uncompressed size cap
/import a.tar.gz b.tar.gz c.tar.gz                 # multiple tarballs
```

## Hardening (per Codex review)

Rejects tarballs containing:
- absolute paths or `..` traversal
- symlinks, hardlinks, devices, FIFOs, sockets
- control characters in entry names
- newline-in-filename (entry-count mismatch detection)
- uncompressed size > `--max-bytes` (default 100 MiB; ceiling 10 GiB)

Extraction uses `--no-same-owner --no-same-permissions` to drop setuid
bits. Snapshot-then-extract defeats TOCTOU swap of the input file.
