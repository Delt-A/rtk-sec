#!/usr/bin/env bash
# End-to-end filter test against real captured output.
#
# `rtk pipe -f` refuses TOML filter names, so instead a stub named after the tool
# is put first on PATH. rtk resolves the tool through PATH, reconstructs the
# command, and matches match_command exactly as it would in a real run — which
# exercises the CR / ANSI / stderr behaviour that inline tests cannot reach.
#
#   replay-test.sh            run every sample
#   replay-test.sh --update   refresh the golden files
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

RTK="$(command -v rtk || echo "$HOME/.local/bin/rtk")"
STUB="$(mktemp -d)"; trap 'rm -rf "$STUB"' EXIT
UPDATE=0
[[ "${1:-}" == "--update" ]] && UPDATE=1

# scenario name -> the argv rtk should see
declare -A CMD=(
  [gobuster-dir]="gobuster dir -u http://127.0.0.1:8080 -w /dev/null"
  [ffuf-dir]="ffuf -u http://127.0.0.1:8080/FUZZ -w /dev/null"
  [feroxbuster-dir]="feroxbuster -u http://127.0.0.1:8080 -w /dev/null"
  [nikto-scan]="nikto -h http://127.0.0.1:8080"
  [whatweb]="whatweb http://127.0.0.1:8080"
  [wafw00f]="wafw00f http://127.0.0.1:8080"
  [sqlmap-scan]="sqlmap -u http://127.0.0.1:8081/?id=1 --batch"
  [nmap-scan]="nmap -sV -p 2200,2280,2225,2253,2299 127.0.0.1"
  [smbclient-recurse]="smbclient //127.0.0.1/LAB -N -c recurse; ls"
)

fail=0
printf '%-20s %10s %10s %8s\n' SCENARIO RAW FILTERED SAVED
for name in $(printf '%s\n' "${!CMD[@]}" | sort); do
  sample="samples/raw/${name}.txt"
  [[ -f "$sample" ]] || { echo "[skip] $name — no sample"; continue; }

  tool="${CMD[$name]%% *}"
  printf '#!/bin/sh\nexec cat "$RTKSEC_SAMPLE"\n' > "$STUB/$tool"
  chmod +x "$STUB/$tool"

  out="$(PATH="$STUB:$PATH" RTKSEC_SAMPLE="$ROOT/$sample" $RTK ${CMD[$name]} 2>&1)"

  golden="samples/golden/${name}.txt"
  if (( UPDATE )); then
    printf '%s\n' "$out" > "$golden"
  elif [[ -f "$golden" ]]; then
    diff -u "$golden" <(printf '%s\n' "$out") || { echo "[FAIL] $name"; fail=1; }
  else
    echo "[warn] $name — no golden file yet (run --update)"
  fi

  raw=$(wc -c < "$sample")
  filt=$(printf '%s\n' "$out" | wc -c)
  printf '%-20s %10d %10d %7d%%\n' "$name" "$raw" "$filt" $(( (raw - filt) * 100 / raw ))
done

exit $fail
