---
name: export
description: Package this host's most-recent ClaudeMeX run as a tarball for transport (USB/scp/Dropbox) when Syncthing or Gitea is unavailable.
---

# /export — package this host's run for non-Syncthing transport

Activates `claudemex export`. Picks the lex-greatest `<host>-<ts>/`
directory matching this machine's hostname and packages it as a gzipped
tarball.

## Usage

```
/export                                    # → claudemex-export-<host>-<ts>.tar.gz
/export --out=mybundle.tar.gz              # custom output filename
/export --from=./other-outputs             # alternative input dir
```

Move the tarball to the merge node by any channel, then run `/import` on
the merge node before `/merge`. See `docs/merge-guide.md`.
