#!/usr/bin/env bash
# claudemex merge — combine per-machine ClaudeMeX runs into common-kernel +
# per-machine extension via majority vote (K = max(2, ceil(N/2))).
#
# See docs/superpowers/specs/2026-05-05-multi-machine-behavior-merge-design.md
# Usage: claudemex merge [--week=YYYY-WW] [--threshold=K] [--from=DIR] [--hosts=h1,h2] [--allow-untrusted-hosts]

set -uo pipefail

# Defence-in-depth (Codex F3): pin PATH to system locations so a
# poisoned PATH cannot shadow tar/gzip/cp/scutil/etc.
PATH=/usr/bin:/bin:/usr/sbin:/sbin
export PATH

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SELF_DIR/lib/meta-yaml.sh"
. "$SELF_DIR/lib/extract-sections.sh"
. "$SELF_DIR/lib/vote-sections.sh"

G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; N_=$'\e[0m'

usage() {
    cat <<'USAGE'
Usage: claudemex merge [--week=YYYY-WW] [--threshold=K] [--from=DIR]
                       [--hosts=h1,h2,h3] [--allow-untrusted-hosts]

Combines per-machine ClaudeMeX runs into a common-kernel + per-machine
extension via section-level majority vote.

Options:
  --week=YYYY-WW      ISO week tag for output dir (default: current ISO week)
  --threshold=K       Override majority-vote threshold (default: max(2, ceil(N/2)))
  --from=DIR          Input dir containing <host>-<ts>/ subdirs (default: ./outputs/)
  --hosts=h1,h2,h3    Explicit comma-separated trusted host whitelist. Any host
                      not in this list is excluded from voting.
                      Overrides ~/.config/claudemex/trusted-hosts file.
  --allow-untrusted-hosts
                      Run without any whitelist (default refuses if no
                      whitelist source is available; this flag is the explicit
                      opt-out — required only when you genuinely want every
                      host that landed in --from to vote).
  -h, --help          Show this help

Trusted-host file (default ~/.config/claudemex/trusted-hosts) is one host per
line, "#" for comments. Override path with $CLAUDEMEX_TRUSTED_HOSTS.

Output:  merged/<YYYY-WW>/{common-kernel/, per-machine-extension/, *-report.md}

Exit codes:
  0  Success
  1  Input missing / N=1 / invalid args / no trust source (without --allow-untrusted-hosts)
  2  Unknown flag / no consensus (no section met K)
USAGE
}

# Parse args
WEEK=$(date +%G-W%V)
FROM="./outputs"
THRESHOLD=""
HOSTS_CSV=""
ALLOW_UNTRUSTED=0
for arg in "$@"; do
    case "$arg" in
        --week=*)        WEEK="${arg#--week=}";;
        --threshold=*)   THRESHOLD="${arg#--threshold=}";;
        --from=*)        FROM="${arg#--from=}";;
        --hosts=*)       HOSTS_CSV="${arg#--hosts=}";;
        --allow-untrusted-hosts) ALLOW_UNTRUSTED=1;;
        -h|--help)       usage; exit 0;;
        *) echo "${R}unknown arg:${N_} $arg" >&2; usage >&2; exit 2;;
    esac
done

# Validate --week (used as a path component below — never let untrusted
# input flow into rm -rf).  Format must be ISO YYYY-Www, e.g. 2026-W18.
case "$WEEK" in
    [0-9][0-9][0-9][0-9]-W[0-9][0-9]) ;;
    *) echo "${R}❌${N_} invalid --week: $WEEK (expected YYYY-Www, e.g. 2026-W18)" >&2; exit 1;;
esac

# Validate --threshold (if user supplied). Reject K<2: K=1 means any single
# host's body becomes "common", which destroys the cross-machine consensus
# guarantee — even more dangerous if one host is compromised. (Codex C3.)
if [ -n "$THRESHOLD" ]; then
    if ! [[ "$THRESHOLD" =~ ^[1-9][0-9]*$ ]]; then
        echo "${R}❌${N_} invalid --threshold: $THRESHOLD (must be positive integer)" >&2
        exit 1
    fi
    if [ "$THRESHOLD" -lt 2 ]; then
        echo "${R}❌${N_} --threshold=$THRESHOLD rejected: must be >= 2 (single-host quorum is unsafe)" >&2
        exit 1
    fi
fi

[ -d "$FROM" ] || { echo "${R}❌${N_} --from dir not found: $FROM" >&2; exit 1; }

# Build the trusted-host whitelist BEFORE host discovery. Three sources, in
# precedence order:
#   1. --hosts=h1,h2,h3 (explicit override)
#   2. file at $CLAUDEMEX_TRUSTED_HOSTS (default ~/.config/claudemex/trusted-hosts)
#      — outside the Syncthing-shared tree by design, so a compromised peer
#      cannot edit it.
#   3. --allow-untrusted-hosts flag (no whitelist; everyone in --from votes)
#
# If none of the three is present, refuse to run. Codex red-team review C1/C2
# proved that without a whitelist a compromised Syncthing peer can stage
# internally-consistent fake hosts (e.g. evil-a-20260506/ + evil-b-20260506/
# with matching host: fields) and reach quorum on a payload of their choice.
# --allow-untrusted-hosts and --hosts are mutually exclusive: passing both
# is contradictory user intent (one declares a whitelist, the other says
# "no whitelist") and previously the latter silently neutered the former.
# Refuse rather than silently pick one.
if [ "$ALLOW_UNTRUSTED" -eq 1 ] && [ -n "$HOSTS_CSV" ]; then
    echo "${R}❌${N_} --allow-untrusted-hosts and --hosts are mutually exclusive" >&2
    echo "    pick one: either declare a whitelist or opt out, not both." >&2
    exit 1
fi

declare -A TRUSTED=()
TRUST_SOURCE=""
TRUSTED_FILE="${CLAUDEMEX_TRUSTED_HOSTS:-$HOME/.config/claudemex/trusted-hosts}"

if [ -n "$HOSTS_CSV" ]; then
    IFS=',' read -ra _hl <<< "$HOSTS_CSV"
    for _h in "${_hl[@]}"; do
        _h="${_h//[[:space:]]/}"
        [ -n "$_h" ] && TRUSTED["$_h"]=1
    done
    TRUST_SOURCE="--hosts flag (${#TRUSTED[@]} entries)"
elif [ "$ALLOW_UNTRUSTED" -ne 1 ] && [ -e "$TRUSTED_FILE" ]; then
    # Codex A1: refuse to read the whitelist if it is a symlink. A
    # compromised peer that can write into ~/.config/claudemex/ (e.g.
    # via misconfigured Syncthing share) could redirect the whitelist
    # to a file they control. Force the whitelist to be a real file.
    if [ -L "$TRUSTED_FILE" ]; then
        echo "${R}❌${N_} trusted-host file is a symlink: $TRUSTED_FILE" >&2
        echo "    refuse to follow symlinks for the whitelist (security)" >&2
        exit 1
    fi
    if [ ! -f "$TRUSTED_FILE" ]; then
        echo "${R}❌${N_} trusted-host path exists but is not a regular file: $TRUSTED_FILE" >&2
        exit 1
    fi
    while IFS= read -r _line || [ -n "$_line" ]; do
        _line="${_line%%#*}"           # strip comment
        _line="${_line//[[:space:]]/}" # strip whitespace
        [ -n "$_line" ] && TRUSTED["$_line"]=1
    done < "$TRUSTED_FILE"
    TRUST_SOURCE="$TRUSTED_FILE (${#TRUSTED[@]} entries)"
fi

if [ "${#TRUSTED[@]}" -eq 0 ] && [ "$ALLOW_UNTRUSTED" -ne 1 ]; then
    cat >&2 <<EOF
${R}❌${N_} no trusted-host whitelist found. Refusing to run.

Multi-machine merge requires you to declare which hostnames are real
machines you control. Without this, a compromised Syncthing peer could
manufacture fake hosts (e.g. evil-a + evil-b with matching layout) and
reach quorum on a malicious payload that lands in your common-kernel.

Pick one:
  1. Pass --hosts=tk-mbp16-m3,h2ejvun (comma-separated)
  2. Create $TRUSTED_FILE
     (one hostname per line, "#" comments allowed)
  3. Pass --allow-untrusted-hosts to opt out (NOT recommended unless
     --from points at a directory you fully control)
EOF
    exit 1
fi

# Discover hosts. Defence-in-depth (Codex adversarial review):
#
#   * dir name MUST be exactly "<host>-<YYYYMMDD>" (Codex C1/C2: bind the
#     declared host to the directory; otherwise an attacker who controls
#     one Syncthing-shared <host>-<ts>/ can stage two fake dirs claiming
#     two different hosts and reach quorum on their own).
#   * `host` field MUST match a strict hostname regex (Codex A2: prevent
#     "../../../tmp/pwn" or shell-meta values from flowing into path
#     components like per-machine-extension/$h/rules/).
#   * future-dated <ts> trailer is rejected entirely (Codex E1: a fake
#     dir like evil-20991231 would silently win lex-sort "latest" forever).
#
# Then group by host field and keep the lex-greatest dir per host (since
# dir names embed YYYYMMDD, this picks the newest run per host).
HOST_RE='^[a-z0-9][a-z0-9._-]{0,62}$'
declare -A HOST_LATEST=()
STALE_THRESHOLD_DAYS=30
NOW_EPOCH=$(date +%s)
declare -a STALE_HOSTS=()
declare -a REJECTED_DIRS=()

for d in "$FROM"/*/; do
    [ -d "$d" ] || continue
    [ -f "$d/run-meta.yaml" ] || continue

    h=$(read_meta_field "$d/run-meta.yaml" host)
    [ -z "$h" ] && continue

    # A2: strict hostname regex
    if ! [[ "$h" =~ $HOST_RE ]]; then
        REJECTED_DIRS+=("${d%/}: host field '$h' is not a valid hostname")
        continue
    fi

    # Whitelist enforcement (Codex C1/C2 deeper fix): if ANY whitelist is
    # active, the host MUST be on it. ALLOW_UNTRUSTED only suppresses the
    # earlier "no whitelist source" abort — it does NOT bypass an explicit
    # whitelist (which would be silently neutering the user's intent).
    # Since --allow-untrusted-hosts is mutually exclusive with --hosts at
    # parse time, an active TRUSTED set here is always a real user-declared
    # whitelist — enforce it unconditionally.
    if [ "${#TRUSTED[@]}" -gt 0 ] && [ -z "${TRUSTED[$h]:-}" ]; then
        REJECTED_DIRS+=("${d%/}: host '$h' not in trust whitelist ($TRUST_SOURCE)")
        continue
    fi

    # C1/C2: dir basename must be exactly "<h>-<8 digits>"
    rd_basename="${d%/}"; rd_basename="${rd_basename##*/}"
    if [[ "$rd_basename" != "$h-"[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9] ]]; then
        REJECTED_DIRS+=("${d%/}: dir name '$rd_basename' does not match required '<host>-<YYYYMMDD>' for host='$h'")
        continue
    fi

    rd_ts="${rd_basename##*-}"
    # Compute age in days (also rejects future-dated dirs at E1)
    ts_epoch=$(date -j -f "%Y%m%d" "$rd_ts" +%s 2>/dev/null || echo 0)
    if [ "$ts_epoch" -le 0 ]; then
        REJECTED_DIRS+=("${d%/}: timestamp '$rd_ts' is not a valid YYYYMMDD")
        continue
    fi
    age_days=$(( (NOW_EPOCH - ts_epoch) / 86400 ))
    if [ "$age_days" -lt 0 ]; then
        # E1: future-dated entries are clock-skew or attack — reject loudly.
        REJECTED_DIRS+=("${d%/}: timestamp '$rd_ts' is in the future (age=${age_days}d)")
        continue
    fi
    [ "$age_days" -gt "$STALE_THRESHOLD_DAYS" ] && STALE_HOSTS+=("$h:${age_days}d")

    existing="${HOST_LATEST[$h]:-}"
    if [ -z "$existing" ] || [[ "$d" > "$existing/" ]]; then
        HOST_LATEST["$h"]="${d%/}"
    fi
done

# Convert dedup'd map → ordered arrays (sort host names for determinism)
declare -a HOSTS=()
declare -a RUN_DIRS=()
while IFS= read -r h; do
    [ -z "$h" ] && continue
    HOSTS+=("$h")
    RUN_DIRS+=("${HOST_LATEST[$h]}")
done < <(printf '%s\n' "${!HOST_LATEST[@]}" | sort)

# Surface rejection reasons (transparency: tell the user why dirs vanished)
if [ "${#REJECTED_DIRS[@]}" -gt 0 ]; then
    echo "${Y}⚠${N_}  rejected ${#REJECTED_DIRS[@]} input directory/ies during host discovery:" >&2
    for r in "${REJECTED_DIRS[@]}"; do echo "    - $r" >&2; done
fi

NCOUNT=${#HOSTS[@]}
if [ "$NCOUNT" -lt 2 ]; then
    echo "${R}❌${N_} merge requires N>=2 hosts; found N=$NCOUNT" >&2
    [ "$NCOUNT" -eq 1 ] && echo "    host: ${HOSTS[0]}" >&2
    exit 1
fi

# Compute threshold
if [ -z "$THRESHOLD" ]; then
    THRESHOLD=$(compute_K "$NCOUNT")
fi

# Range-check threshold against host count
if [ "$THRESHOLD" -gt "$NCOUNT" ]; then
    echo "${R}❌${N_} --threshold=$THRESHOLD exceeds host count N=$NCOUNT" >&2
    exit 1
fi

# Surface stale-run warnings (one line per host, then continue)
if [ "${#STALE_HOSTS[@]}" -gt 0 ]; then
    echo "${Y}⚠${N_}  stale latest runs (>${STALE_THRESHOLD_DAYS}d): ${STALE_HOSTS[*]}" >&2
fi

OUT_DIR="merged/$WEEK"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR/common-kernel/rules" "$OUT_DIR/per-machine-extension"
for h in "${HOSTS[@]}"; do
    mkdir -p "$OUT_DIR/per-machine-extension/$h/rules"
done

echo "${G}▸${N_} Inputs: N=$NCOUNT (${HOSTS[*]}), K=$THRESHOLD, week=$WEEK"

# Codex B1+B2 mitigation: detect hosts whose entire rules/ trees hash
# identically. ClaudeMeX has no per-host cryptographic identity, so a
# compromised machine could Syncthing-replicate its own outputs/ into a
# fake-host-named directory ("evil-clone"). Two real machines almost never
# produce byte-identical rules/ trees (machine-specific §11 archives,
# Karpathy/Tacit retrofit dates, etc), so an exact tree-hash collision
# between two trusted hosts is a strong signal of single-source cloning.
declare -A _HOST_TREE_HASH=()
declare -A _SEEN_TREE_HASH=()
declare -a _CLONE_PAIRS=()
for _i in "${!HOSTS[@]}"; do
    _h="${HOSTS[$_i]}"
    _rdir="${RUN_DIRS[$_i]}/rules"
    if [ -d "$_rdir" ]; then
        # Hash relative paths + contents under rdir. cd into the dir so the
        # find output is path-relative ("./01-identity.md"); two hosts whose
        # rules/ are byte-identical will produce identical tree hashes
        # regardless of where on disk they live.
        _th=$(cd "$_rdir" 2>/dev/null && \
              find . -type f -name '*.md' | LC_ALL=C sort | \
              while IFS= read -r _rel; do
                  printf '###%s###\n' "$_rel"
                  cat "$_rel" 2>/dev/null
              done | shasum -a 256 | awk '{print $1}')
        _HOST_TREE_HASH["$_h"]="$_th"
        if [ -n "${_SEEN_TREE_HASH[$_th]:-}" ]; then
            _CLONE_PAIRS+=("${_SEEN_TREE_HASH[$_th]} <-> $_h")
        else
            _SEEN_TREE_HASH["$_th"]="$_h"
        fi
    fi
done
if [ "${#_CLONE_PAIRS[@]}" -gt 0 ]; then
    echo "${R}⚠  SECURITY:${N_} hosts with byte-identical rules/ trees detected:" >&2
    for _cp in "${_CLONE_PAIRS[@]}"; do echo "    $_cp" >&2; done
    echo "    This is unusual and may indicate Syncthing-replicated outputs/" >&2
    echo "    from one host masquerading as multiple. Verify each host ran" >&2
    echo "    its own 'claudemex generate' before deploying the merge result." >&2
    echo "    (Continuing — this is a warning, not a hard failure.)" >&2
fi
unset _HOST_TREE_HASH _SEEN_TREE_HASH

# Build section index: section_id → list of "host:hash:bodyfile" tokens
declare -a TMP_FILES_TO_CLEAN=()
declare -A SECTION_VOTES=()
declare -A SECTION_FILES=()

for i in "${!HOSTS[@]}"; do
    host="${HOSTS[$i]}"
    rdir="${RUN_DIRS[$i]}/rules"
    [ -d "$rdir" ] || continue
    for rf in "$rdir"/*.md; do
        [ -f "$rf" ] || continue
        while IFS=$'\t' read -r sid bodyfile; do
            [ -z "$sid" ] && continue
            TMP_FILES_TO_CLEAN+=("$bodyfile")
            normhash=$(normalize_body < "$bodyfile" | hash_body)
            SECTION_VOTES["$sid"]="${SECTION_VOTES[$sid]:-}|$host:$normhash:$bodyfile"
            SECTION_FILES["$sid"]="$(basename "$rf")"
        done < <(extract_sections "$rf")
    done
done

# Cleanup our extracted tmp files at exit
cleanup_tmps() {
    for f in "${TMP_FILES_TO_CLEAN[@]:-}"; do
        [ -n "$f" ] && [ -f "$f" ] && rm -f "$f"
    done
}
trap cleanup_tmps EXIT

# Tally votes
COMMON_COUNT=0
declare -A EXT_COUNT=()
declare -a DRIFT_LINES=()
declare -a DRIFT_SIDS=()       # ordered, unique sid list (drift only)
declare -A DRIFT_DETAILS=()    # sid → multi-line "host|short-hash|lines|marker"
declare -A DRIFT_STATUS=()     # sid → MINORITY|NO-CONSENSUS

# Iterate sids in deterministic (sorted) order so the same inputs always
# produce identical common-kernel/rules/<file>.md and per-machine-extension
# files (associative array key order is implementation-defined).
while IFS= read -r sid; do
    [ -z "$sid" ] && continue
    raw="${SECTION_VOTES[$sid]}"
    # Strip leading | then split on |
    raw="${raw#|}"
    IFS='|' read -ra tokens <<< "$raw"

    declare -a HASHES=()
    declare -A H2BODY=()
    declare -A HASH_HOSTS=()
    for tok in "${tokens[@]}"; do
        IFS=: read -r h hsh bf <<< "$tok"
        HASHES+=("$hsh")
        H2BODY["$hsh"]="$bf"
        HASH_HOSTS["$hsh"]="${HASH_HOSTS[$hsh]:-} $h"
    done

    winner=$(vote_section_hashes "$THRESHOLD" "${HASHES[@]}" 2>/dev/null || true)
    rule_file="${SECTION_FILES[$sid]}"
    title="${sid#*::}"

    # Pre-build a per-host detail block (host|short-hash|line-count|marker)
    # used by both branches when this section is a drift.
    detail=""
    for tok in "${tokens[@]}"; do
        IFS=: read -r h hsh bf <<< "$tok"
        ln=$(awk 'END{print NR}' "$bf")
        marker=""
        [ -n "$winner" ] && [ "$hsh" = "$winner" ] && marker="majority"
        detail+="$h|${hsh:0:8}|$ln|$marker"$'\n'
    done

    if [ -n "$winner" ]; then
        # Append to common-kernel/rules/<file>
        target="$OUT_DIR/common-kernel/rules/$rule_file"
        if [ ! -f "$target" ]; then
            echo "# ${rule_file%.md}" > "$target"
            echo >> "$target"
        fi
        {
            echo "## $title"
            echo
            normalize_body < "${H2BODY[$winner]}"
            echo
        } >> "$target"
        COMMON_COUNT=$((COMMON_COUNT + 1))

        # Minority hosts: write their (non-winning) body to per-machine-extension
        # AND record drift lines for the report.
        for tok in "${tokens[@]}"; do
            IFS=: read -r h hsh bf <<< "$tok"
            [ "$hsh" = "$winner" ] && continue
            target="$OUT_DIR/per-machine-extension/$h/rules/$rule_file"
            if [ ! -f "$target" ]; then
                echo "# ${rule_file%.md}" > "$target"
                echo >> "$target"
            fi
            {
                echo "## $title"
                echo
                normalize_body < "$bf"
                echo
            } >> "$target"
            EXT_COUNT["$h"]=$((${EXT_COUNT[$h]:-0} + 1))
        done
        # Record drift only if there is at least one non-majority hash
        # (a section where every host happens to agree perfectly is NOT drift)
        has_minority=0
        for hsh in "${!HASH_HOSTS[@]}"; do
            [ "$hsh" = "$winner" ] && continue
            has_minority=1
            DRIFT_LINES+=("$sid|MINORITY|${HASH_HOSTS[$hsh]## }|short-hash:${hsh:0:8}")
        done
        if [ "$has_minority" -eq 1 ]; then
            DRIFT_SIDS+=("$sid")
            DRIFT_STATUS["$sid"]="MINORITY"
            DRIFT_DETAILS["$sid"]="$detail"
        fi
    else
        # No consensus → goes to extension for each contributing host
        for tok in "${tokens[@]}"; do
            IFS=: read -r h hsh bf <<< "$tok"
            target="$OUT_DIR/per-machine-extension/$h/rules/$rule_file"
            if [ ! -f "$target" ]; then
                echo "# ${rule_file%.md}" > "$target"
                echo >> "$target"
            fi
            {
                echo "## $title"
                echo
                normalize_body < "$bf"
                echo
            } >> "$target"
            EXT_COUNT["$h"]=$((${EXT_COUNT[$h]:-0} + 1))
        done
        DRIFT_LINES+=("$sid|NO-CONSENSUS|all-divergent|N/A")
        DRIFT_SIDS+=("$sid")
        DRIFT_STATUS["$sid"]="NO-CONSENSUS"
        DRIFT_DETAILS["$sid"]="$detail"
    fi

    unset HASHES H2BODY HASH_HOSTS
done < <(printf '%s\n' "${!SECTION_VOTES[@]}" | sort)

if [ "$COMMON_COUNT" -eq 0 ]; then
    echo "${R}❌${N_} No section met K=$THRESHOLD threshold" >&2
    rm -rf "$OUT_DIR"
    exit 2
fi

# Write meta — build comma-separated host list without mutating IFS
host_csv=$(printf '%s,' "${HOSTS[@]}"); host_csv="${host_csv%,}"
write_kernel_meta "$OUT_DIR/common-kernel/kernel-meta.yaml" "$THRESHOLD" "$COMMON_COUNT" "$host_csv"

# Write merge-report.md
{
    echo "# Merge Report — $WEEK"
    echo
    echo "- Contributing hosts: ${HOSTS[*]}"
    echo "- N = $NCOUNT, K = $THRESHOLD"
    echo "- Common sections:        $COMMON_COUNT"
    echo "- Per-machine extension counts:"
    for h in "${HOSTS[@]}"; do
        echo "  - $h: ${EXT_COUNT[$h]:-0}"
    done
    echo
    echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} > "$OUT_DIR/merge-report.md"

# Write drift-report.md
{
    echo "# Drift Report — $WEEK"
    echo
    echo "Per-section divergence detected during merge. Review and decide whether to promote or accept."
    echo
    if [ "${#DRIFT_LINES[@]}" -eq 0 ]; then
        echo "*No drift detected.*"
    else
        echo "## Summary"
        echo
        echo "| Section | Status | Hosts | Notes |"
        echo "|---|---|---|---|"
        for line in "${DRIFT_LINES[@]}"; do
            IFS='|' read -r sid status hosts notes <<< "$line"
            echo "| \`$sid\` | $status | $hosts | $notes |"
        done
        echo
        echo "## Details"
        echo
        echo "_For each drifted section, lists every contributing host with its short content hash and line count. Hosts that share a hash had identical bodies; the \`majority\` marker (when present) identifies the body that landed in \`common-kernel/\`._"
        echo
        for sid in "${DRIFT_SIDS[@]}"; do
            echo "### \`$sid\` (${DRIFT_STATUS[$sid]})"
            echo
            echo "| Host | Short hash | Lines | Note |"
            echo "|---|---|---|---|"
            while IFS='|' read -r dh dhsh dln dmk; do
                [ -z "$dh" ] && continue
                echo "| $dh | \`$dhsh\` | $dln | $dmk |"
            done <<< "${DRIFT_DETAILS[$sid]}"
            echo
        done
    fi
} > "$OUT_DIR/drift-report.md"

# NOTE: no automatic redact-scan / release-sanitize on merge output.
# Inputs are user MAX-tier outputs that legitimately contain the user's own
# IPs / hostnames / personal codenames; release-grade redaction would always
# block them. Merge output stays on this machine (apply writes to
# ~/.claude/CLAUDE.md, never published), so content-redaction is the wrong
# gate here. If the user wants to publish a kernel, they invoke redact-scan
# explicitly. See spec §11 (Sanity Gate Integration) for the design note.

echo "${G}✓${N_} merge complete → $OUT_DIR"
echo "${G}✓${N_} common: $COMMON_COUNT, extensions: $(for h in "${HOSTS[@]}"; do echo -n "${EXT_COUNT[$h]:-0} "; done)"
echo "${G}▸${N_} read $OUT_DIR/merge-report.md and $OUT_DIR/drift-report.md before deploy"
exit 0
