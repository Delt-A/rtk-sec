#!/usr/bin/env bash
# Install rtk-sec filters into ~/.config/rtk/filters.toml.
#
#   ./install.sh            install or upgrade
#   ./install.sh --dry-run  print the merged result, touch nothing
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

VERSION="$(cat VERSION)"
BEGIN="# >>> rtk-sec BEGIN v${VERSION} — managed block, do not edit by hand"
END="# <<< rtk-sec END"
TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/rtk/filters.toml"
DRY_RUN=0
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=1

RTK="$(command -v rtk || echo "$HOME/.local/bin/rtk")"
[[ -x "$RTK" ]] || { echo "rtk not found — install it first" >&2; exit 1; }

have="$("$RTK" --version | awk '{print $2}')"
printf '%s\n0.45.0\n' "$have" | sort -V -C || {
  echo "rtk $have is older than the required 0.45.0" >&2; exit 1; }

command -v python3 >/dev/null || { echo "python3 required" >&2; exit 1; }

./tools/build-filters.sh >/dev/null
./tools/check-collisions.sh

# Any managed block from a previous install is dropped, so re-running upgrades
# cleanly instead of appending a second copy.
strip_managed() {
  awk -v b="# >>> rtk-sec BEGIN" -v e="$END" '
    index($0, b) == 1 { skip = 1; next }
    $0 == e          { skip = 0; next }
    !skip
  ' "$1"
}

merged="$(mktemp)"; trap 'rm -f "$merged"' EXIT
if [[ -f "$TARGET" ]]; then
  strip_managed "$TARGET" > "$merged"
else
  mkdir -p "$(dirname "$TARGET")"
  : > "$merged"
fi

# A bare key written after a table header binds to that table, so schema_version
# has to land above the first [ line or it silently becomes filters.X.schema_version.
if ! grep -qE '^\s*schema_version\s*=' "$merged"; then
  tmp="$(mktemp)"
  awk 'BEGIN{done=0} /^\[/ && !done {print "schema_version = 1"; print ""; done=1} {print}
       END{if(!done) print "schema_version = 1"}' "$merged" > "$tmp"
  mv "$tmp" "$merged"
fi
if [[ "$(grep -cE '^\s*schema_version\s*=' "$merged")" -gt 1 ]]; then
  echo "$TARGET has multiple schema_version keys — resolve by hand" >&2; exit 1
fi

{ printf '\n%s\n' "$BEGIN"; ./tools/build-filters.sh --stdout; printf '%s\n' "$END"; } >> "$merged"

if (( DRY_RUN )); then cat "$merged"; exit 0; fi

backup=""
if [[ -f "$TARGET" ]]; then
  backup="${TARGET}.bak.$(date +%s)"
  cp "$TARGET" "$backup"
  ls -1t "${TARGET}".bak.* 2>/dev/null | tail -n +11 | xargs -r rm -f
fi

cp "$merged" "$TARGET"

# Phase 0: the user-global filter file is inert until trusted, and rtk verify only
# ever reads inline tests from a project-local file — hence the repo-local gate below.
"$RTK" trust -y >/dev/null 2>&1 || true

if ! "$RTK" verify --require-all 2>&1 | tee /tmp/rtksec-verify.log | grep -q 'tests passed'; then
  echo "rtk verify failed — restoring previous filters.toml" >&2
  cat /tmp/rtksec-verify.log >&2
  [[ -n "$backup" ]] && cp "$backup" "$TARGET"
  exit 1
fi

install -Dm755 bin/rtk-sec "$HOME/.local/bin/rtk-sec"

# RTK.md is already imported into CLAUDE.md, so a sibling file plus one @import
# line keeps our guidance out of the user's own notes.
CLAUDE_DIR="$HOME/.claude"
if [[ -d "$CLAUDE_DIR" ]]; then
  cp rtk-sec.md "$CLAUDE_DIR/rtk-sec.md"
  if [[ -f "$CLAUDE_DIR/RTK.md" ]] && ! grep -q '^@rtk-sec.md' "$CLAUDE_DIR/RTK.md"; then
    cp "$CLAUDE_DIR/RTK.md" "$CLAUDE_DIR/RTK.md.bak.$(date +%s)"
    printf '\n@rtk-sec.md\n' >> "$CLAUDE_DIR/RTK.md"
  fi
fi

loaded="$(RTK_TOML_DEBUG=1 "$RTK" echo rtksec-smoke 2>&1 | grep -oE '\([0-9]+ filters loaded\)' || true)"
echo "[ok] rtk-sec v${VERSION} installed to $TARGET ${loaded}"
echo "     wrapper: ~/.local/bin/rtk-sec   guidance: ~/.claude/rtk-sec.md"
[[ -n "$backup" ]] && echo "     backup: $backup"
echo "     run 'rtk trust -y' if a later shell reports untrusted filters"
