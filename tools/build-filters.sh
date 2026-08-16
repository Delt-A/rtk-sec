#!/usr/bin/env bash
# Concatenate filters/**/*.toml into a single rtk-compatible filter file.
# Mirrors upstream's own layout: one leading schema_version, then
# "# --- <name>.toml ---" separators.
#
#   build-filters.sh            -> writes dist/rtk-sec.filters.toml and .rtk/filters.toml
#   build-filters.sh --stdout   -> writes the block to stdout, no schema_version
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

emit_block() {
  local f
  while IFS= read -r f; do
    printf '# --- %s ---\n' "$(basename "$f")"
    cat "$f"
    printf '\n'
  done < <(find filters -name '*.toml' | sort)
}

if [[ "${1:-}" == "--stdout" ]]; then
  emit_block
  exit 0
fi

mkdir -p dist
{
  printf 'schema_version = 1\n\n'
  emit_block
} > dist/rtk-sec.filters.toml

# R12: never let malformed TOML reach ~/.config or the test harness.
python3 - dist/rtk-sec.filters.toml <<'PY'
import sys, tomllib
path = sys.argv[1]
with open(path, "rb") as fh:
    doc = tomllib.load(fh)
filters = doc.get("filters", {})
tests = doc.get("tests", {})
if not filters:
    sys.exit(f"{path}: no [filters.*] tables found")
missing = sorted(set(filters) - set(tests))
if missing:
    sys.exit(f"{path}: filters without inline tests: {', '.join(missing)}")
print(f"{path}: OK — {len(filters)} filters, "
      f"{sum(len(v) for v in tests.values())} inline tests")
PY

# The repo's own .rtk/filters.toml is what `rtk verify` reads: Phase 0 established
# that inline tests are only discovered from a project-local file, never the global one.
cp dist/rtk-sec.filters.toml .rtk/filters.toml
echo "wrote dist/rtk-sec.filters.toml and .rtk/filters.toml"
