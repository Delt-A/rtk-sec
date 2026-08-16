#!/usr/bin/env bash
# Minimal zero-dependency lab target for sample capture.
# Binds to loopback only. Seeds paths that common wordlists actually contain,
# so scans produce a realistic mix of 200/301/403/404.
set -euo pipefail

PORT="${1:-8080}"
ROOT="$(mktemp -d /tmp/rtksec-lab.XXXXXX)"

mkdir -p "$ROOT"/{admin,icons,backup,.git,cgi-bin,images,css,js}
echo '<html><title>rtk-sec lab</title><body>index</body></html>' > "$ROOT/index.html"
echo 'admin panel'      > "$ROOT/admin/index.html"
echo 'README'           > "$ROOT/icons/README"
echo 'ref: refs/heads/main' > "$ROOT/.git/HEAD"
echo 'backup'           > "$ROOT/backup/index.html"
echo 'body{}'           > "$ROOT/css/style.css"
echo 'var x=1'          > "$ROOT/js/app.js"
echo 'secret'           > "$ROOT/config.php"
echo 'test'             > "$ROOT/test.html"

echo "lab root: $ROOT"
echo "serving on http://127.0.0.1:$PORT (loopback only)"
exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT"
