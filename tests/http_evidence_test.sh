#!/usr/bin/env bash
# http-evidence.sh against a local HTTP server
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
H="$REPO/bin/http-evidence.sh"
T=$(mktemp -d)
export AGENT_WORKFLOW_STATE="$T/st"; mkdir -p "$AGENT_WORKFLOW_STATE"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY; export no_proxy='*' NO_PROXY='*'
PORT=$((30000 + RANDOM % 20000))
python3 -I - "$PORT" > "$T/server.log" 2>&1 <<'PY' &
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def reply(self, code, body):
        b = json.dumps(body).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Set-Cookie", "sid=SECRETCOOKIE"); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith("/missing"): return self.reply(404, {"error": "not found"})
        self.reply(200, {"id": 7, "author": "budi", "accessToken": "TOKVALUE", "items": [{"password": "PW1"}]})
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0)); body = json.loads(self.rfile.read(n) or b"{}")
        self.reply(201, {"echo": body})
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
PY
SRV=$!
trap 'kill $SRV 2>/dev/null; rm -rf "$T"' EXIT
for _ in $(seq 1 50); do (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null && break; sleep 0.1; done
B="http://127.0.0.1:$PORT"

out=$("$H" GET "$B/orders/7?token=QTOK&page=2" -H "Authorization: Bearer HDRSECRET" --label TC1 --note "AC1 detail pesanan"); rc=$?
assert_eq 0 "$rc" "GET ok"
has() { printf '%s' "$out" | grep -qF -- "$1" && echo yes || echo no; }
assert_eq yes "$(has '#### TC1 — GET /orders/7')" "heading with label + path"
assert_eq yes "$(has 'Response: **200**')" "status"
assert_eq yes "$(has 'Catatan: AC1 detail pesanan')" "note"
assert_eq yes "$(has '"author": "budi"')" "non-secret field kept (author is not auth)"
assert_eq yes "$(has 'page=2')" "non-secret query kept"
for s in HDRSECRET QTOK TOKVALUE PW1 SECRETCOOKIE; do assert_eq no "$(has "$s")" "secret $s masked"; done
assert_eq yes "$(has 'Authorization: [disamarkan]')" "auth header masked"

out=$("$H" POST "$B/orders" -d '{"note":"PROJ-12 uji","password":"BODYPW"}' --out "$T/r/uji.md"); rc=$?
assert_eq 0 "$rc" "POST to local dev ok"
assert_eq yes "$(printf '%s' "$out" | grep -q "status=201 .*out=$T/r/uji.md" && echo yes || echo no)" "summary line with --out"
f=$(cat "$T/r/uji.md")
assert_eq no "$(printf '%s' "$f" | grep -q BODYPW && echo yes || echo no)" "request body secret masked (and in echo)"
assert_eq yes "$(printf '%s' "$f" | grep -q 'PROJ-12 uji' && echo yes || echo no)" "request body kept"
"$H" GET "$B/missing" --out "$T/r/uji.md" >/dev/null; rc=$?
assert_eq 0 "$rc" "404 still exit 0 (recorded)"
assert_eq 2 "$(grep -c '^#### ' "$T/r/uji.md")" "--out appends"
assert_eq yes "$(grep -q 'Response: \*\*404\*\*' "$T/r/uji.md" && echo yes || echo no)" "404 recorded"

assert_exit 2 "--safe refuses POST" -- "$H" POST "$B/orders" -d '{}' --safe
assert_exit 0 "--safe allows GET" -- "$H" GET "$B/orders/1" --safe
echo "127.0.0.1" > "$AGENT_WORKFLOW_STATE/prod-hosts.txt"
assert_exit 2 "prod host refuses DELETE without --safe" -- "$H" DELETE "$B/orders/1"
assert_exit 0 "prod host allows HEAD" -- "$H" HEAD "$B/orders/1"
rm "$AGENT_WORKFLOW_STATE/prod-hosts.txt"
out=$("$H" GET "http://127.0.0.1:1/x"); rc=$?
assert_eq 1 "$rc" "connection refused -> exit 1"
assert_eq yes "$(printf '%s' "$out" | grep -q 'gagal terhubung' && echo yes || echo no)" "network error recorded"
"$H" GET "$B/orders/7" --max-body 20 > "$T/cut.md"
assert_eq yes "$(grep -q 'dipotong' "$T/cut.md" && echo yes || echo no)" "--max-body truncates"
assert_exit 2 "usage" -- "$H" GET
assert_exit 2 "bad url" -- "$H" GET ftp://x
assert_exit 2 "bad header" -- "$H" GET "$B/x" -H nocolon

exit $((FAILS > 0))
