# Contributing to ClaudeMeX

Thanks for considering a contribution. The project is small but
opinionated — please read this short guide before opening a PR.

## Project shape

- The product is a single Markdown prompt
  (`TKX-CLAUDE-CONFIG-GENERATOR-PROMPT.md`) plus a small Bash
  release-toolchain (`scripts/redact-scan.sh`,
  `scripts/structural-gate.sh`, `scripts/deploy.sh`).
- The skill bundle lives at `skills/claudemex/`. Root `scripts/` and
  `skills/claudemex/scripts/` are byte-identical mirrors enforced by the
  TKX gitx-release dual-source gate.
- Tests are plain `bash` scripts. `tests/run_all.sh` is the single entry
  point.

## Development setup

Mac / Linux with `bash`, `grep`, `sed`, `awk`, `find`, `shasum`, `git`.
No language runtime needed.

```bash
git clone https://github.com/tkxlab-ai/claude-code-config-generator.git
cd claude-code-config-generator
bash tests/run_all.sh   # should be green (skips for outputs/-dependent suites)
```

## Build / run / test

There is no build step. To run:

```bash
bash install.sh                                  # install into ~/.claude/skills/claudemex/
bash tests/run_all.sh                            # full suite
RUN_ALL_OPTIONAL=1 bash tests/run_all.sh         # include drift detection
bash scripts/redact-scan.sh Release/v<X.Y.Z>/    # pre-release sanity gate
```

## Coding conventions

Match what's already in the repo:

- **Bash**: portable POSIX-ish where possible. BSD `grep` / `sed`
  compatibility is required (we develop on macOS). Always quote
  variables. `set -euo pipefail` at the top of new scripts.
- **No new external dependencies** without a ticket — the redact-scan and
  release pipeline are deliberately zero-dep.
- **Test fixtures with bad-pattern strings** (fake AWS keys, etc.) belong
  under `tests/` and must be whitelisted in `.sanitize-ignore`.
- **Private identifiers** (real IPs, machine names, project codenames)
  must never land in tracked files. RFC 5737 IPs are fine; `EXAMPLE-`
  prefixed machine names are fine. `redact-scan.sh` running tree-wide
  must report `== CLEAN ==`.

## Adding a test

1. Drop `tests/test-<short-name>.sh` (executable, exit 0 on success).
2. Re-run `bash tests/run_all.sh` — it auto-discovers `test-*.sh`.
3. If your test is per-machine (depends on `outputs/` or other gitignored
   state), add the marker `# RUN_ALL: optional` near the top so it's
   opt-in (gate behind `RUN_ALL_OPTIONAL=1`).
4. If it requires gitignored content, prefer a skip-guard pattern:

```bash
if [ ! -d "$PROJECT_ROOT/outputs" ]; then
  echo "SKIP: outputs/ missing — run the generator first"
  exit 0
fi
```

## Pull request checklist

Before opening a PR:

- [ ] `bash tests/run_all.sh` is green
- [ ] `bash -n` clean on every script you touched
- [ ] `bash scripts/redact-scan.sh .` reports `== CLEAN ==` on the
      tracked-only tree (use `git ls-files | xargs cp` to a tmp dir)
- [ ] No new private identifiers in any tracked file
- [ ] `scripts/` and `skills/claudemex/scripts/` are byte-identical
      (`diff -rq` clean)
- [ ] `Release/CHANGELOG.md` updated with a one-line entry under the
      next planned version (or "Unreleased")
- [ ] Commit message follows the existing style: short imperative title,
      body explaining the WHY, optional Co-Authored-By trailer

## Reporting issues

- Bugs: please include a minimal reproducer (one-line `redact-scan` invocation,
  one-line `deploy.sh` call, etc.) and the expected vs actual output.
- Security: please do **not** open a public issue for credential leak / detector
  bypasses. Email the maintainer (see `LICENSE` for contact path).

## Release process

Releases are produced via the TKX gitx-release pipeline. See
`Release/CHANGELOG.md` for the version timeline and `Release/<v>/` for
each cut bundle. Maintainers run:

```bash
PROJECT_ROOT="$(pwd)" SKILL_NAME=claudemex \
  bash ~/.claude/skills/gitx-release/scripts/gitx-release.sh
```

Tagging and pushing to the GitHub remote is a manual step performed by
the maintainer after review.

## License

By contributing you agree that your contributions are licensed under the
MIT License (same as the project).
