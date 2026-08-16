#!/usr/bin/env bash
# Lint rtk-sec filters against the installed rtk binary.
#
#   1. name collision  -> duplicate TOML table key, breaks the whole merged file (abort)
#   2. keep-list without error patterns -> R2, a filter that can hide a failed scan (abort)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RTK="$(command -v rtk || echo "$HOME/.local/bin/rtk")"
[[ -x "$RTK" ]] || { echo "rtk not found" >&2; exit 1; }

strings -a -n 6 "$RTK" | grep -oE '^\[filters\.[a-z0-9._-]+\]$' \
  | sed -E 's/^\[filters\.(.*)\]$/\1/' | sort -u > /tmp/rtksec-builtins.txt

./tools/build-filters.sh >/dev/null

python3 - <<'PY'
import sys, tomllib

with open("dist/rtk-sec.filters.toml", "rb") as fh:
    ours = tomllib.load(fh)["filters"]
builtins = set(open("/tmp/rtksec-builtins.txt").read().split())

fail = False

clash = sorted(set(ours) & builtins)
if clash:
    print(f"[FAIL] name collision with rtk builtins: {', '.join(clash)}")
    fail = True

# R2: a keep-mode filter drops everything it does not explicitly match, so a
# connection failure on stderr vanishes and an aborted scan reads as "nothing found".
REQUIRED = ("error", "refused")
for name, spec in sorted(ours.items()):
    keep = spec.get("keep_lines_matching")
    if not keep:
        continue
    joined = " ".join(keep).lower()
    if not all(tok in joined for tok in REQUIRED):
        print(f"[FAIL] {name}: keep_lines_matching lacks mandatory error patterns")
        fail = True
    if not spec.get("filter_stderr"):
        print(f"[WARN] {name}: filter_stderr not set")

# match_output replaces the entire output; banned until a tee guarantee exists.
for name, spec in sorted(ours.items()):
    if spec.get("match_output"):
        print(f"[FAIL] {name}: match_output is banned in v1")
        fail = True

print(f"[FAIL] lint failed" if fail else f"[ok] {len(ours)} filters, no collisions")
sys.exit(1 if fail else 0)
PY
