#!/usr/bin/env bash
# Remove the rtk-sec managed block from ~/.config/rtk/filters.toml.
set -euo pipefail

TARGET="${XDG_CONFIG_HOME:-$HOME/.config}/rtk/filters.toml"
END="# <<< rtk-sec END"
[[ -f "$TARGET" ]] || { echo "nothing to do — $TARGET does not exist"; exit 0; }

grep -q 'rtk-sec BEGIN' "$TARGET" || { echo "nothing to do — no rtk-sec block found"; exit 0; }

cp "$TARGET" "${TARGET}.bak.$(date +%s)"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
awk -v b="# >>> rtk-sec BEGIN" -v e="$END" '
  index($0, b) == 1 { skip = 1; next }
  $0 == e          { skip = 0; next }
  !skip
' "$TARGET" > "$tmp"
mv "$tmp" "$TARGET"

rm -f "$HOME/.local/bin/rtk-sec" "$HOME/.claude/rtk-sec.md"
if [[ -f "$HOME/.claude/RTK.md" ]] && grep -q '^@rtk-sec.md' "$HOME/.claude/RTK.md"; then
  tmp2="$(mktemp)"
  grep -v '^@rtk-sec.md' "$HOME/.claude/RTK.md" > "$tmp2"
  mv "$tmp2" "$HOME/.claude/RTK.md"
fi

echo "[ok] rtk-sec block removed from $TARGET"
echo "     [tee] settings in config.toml were not modified by install.sh and are left as-is"
