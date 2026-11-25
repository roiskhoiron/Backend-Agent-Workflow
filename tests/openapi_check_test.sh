#!/usr/bin/env bash
# openapi-check.sh: validate (standard OpenAPI 3.x) + diff (code-generated spec vs contract)
source "$(dirname "$0")/lib.sh"
REPO="$(cd "$(dirname "$0")/.." && pwd -P)"
O="$REPO/bin/openapi-check.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

cat > "$T/contract.yaml" <<'Y'
openapi: 3.1.0
info: {title: Orders, version: 1.2.0}
paths:
  /orders/{id}:
    get:
      responses:
        "200":
          content:
            application/json:
              schema: {$ref: "#/components/schemas/Order"}
        "403": {description: bukan pemilik}
        "404": {description: tidak ada}
  /orders:
    post:
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required: [note, items]
              properties: {note: {type: string}, items: {type: array}}
      responses:
        "201": {description: dibuat}
        "422": {description: tidak valid}
  /health:
    get:
      responses: {"200": {description: ok}}
components:
  schemas:
    Order:
      allOf:
        - {$ref: "#/components/schemas/Base"}
        - type: object
          properties: {note: {type: string}, total: {type: number}}
    Base:
      type: object
      properties: {id: {type: integer}}
Y
# what the code's generator produced: same API, path param named differently, JSON
python3 -c '
import json, sys, yaml
s = yaml.safe_load(open(sys.argv[1]))
s["paths"]["/orders/{orderId}"] = s["paths"].pop("/orders/{id}")
json.dump(s, open(sys.argv[2], "w"))' "$T/contract.yaml" "$T/gen.json"

assert_exit 0 "valid 3.1 YAML" -- "$O" validate "$T/contract.yaml"
assert_exit 0 "valid generated JSON" -- "$O" validate "$T/gen.json"
assert_exit 0 "same API (param name differs)" -- "$O" diff "$T/contract.yaml" "$T/gen.json"
assert_eq "OK spec kode sesuai contract" "$("$O" diff "$T/contract.yaml" "$T/gen.json")" "ok message"

# drift in the code: 403 gone, total gone, extra field, note not required, endpoint missing, extra endpoint
python3 -c '
import json, sys
s = json.load(open(sys.argv[1]))
g = s["paths"]["/orders/{orderId}"]["get"]["responses"]; del g["403"]
s["components"]["schemas"]["Order"]["allOf"][1]["properties"] = {"note": {"type": "string"}, "debug": {"type": "string"}}
s["paths"]["/orders"]["post"]["requestBody"]["content"]["application/json"]["schema"]["required"] = ["items"]
del s["paths"]["/health"]
s["paths"]["/internal/reset"] = {"post": {"responses": {"204": {"description": "x"}}}}
json.dump(s, open(sys.argv[2], "w"))' "$T/gen.json" "$T/drift.json"
out=$("$O" diff "$T/contract.yaml" "$T/drift.json"); rc=$?
assert_eq 1 "$rc" "drift -> exit 1"
has() { printf '%s\n' "$out" | grep -qF -- "$1" && echo yes || echo no; }
assert_eq yes "$(has 'status-hilang GET /orders/{id}: 403')" "missing status code"
assert_eq yes "$(has "response-field-hilang GET /orders/{id} 200: ['total']")" "missing response field (allOf resolved)"
assert_eq yes "$(has "response-field-tambahan GET /orders/{id} 200: ['debug']")" "extra response field"
assert_eq yes "$(has "request-wajib POST /orders: contract ['items', 'note'] vs kode ['items']")" "required request fields differ"
assert_eq yes "$(has 'hilang-di-kode GET /health')" "endpoint missing in code"
assert_eq yes "$(has 'tidak-di-contract POST /internal/reset')" "endpoint not in contract"
out=$("$O" diff "$T/contract.yaml" "$T/drift.json" --paths '^/health'); rc=$?
assert_eq "hilang-di-kode GET /health: ada di contract, tidak ada di spec kode" "$out" "--paths limits to ticket endpoints"

# not standard OpenAPI 3
printf '{"swagger":"2.0","info":{"title":"x","version":"1"},"paths":{}}' > "$T/sw2.json"
out=$("$O" validate "$T/sw2.json"); rc=$?
assert_eq 1 "$rc" "Swagger 2.0 refused"
assert_eq yes "$(printf '%s' "$out" | grep -q swagger2openapi && echo yes || echo no)" "hint: convert or upgrade generator"
printf 'openapi: 3.1.0\ninfo: {title: x}\npaths:\n  /a:\n    get: {}\n  b:\n    post:\n      responses: {"200": {$ref: "#/components/responses/Nope"}}\n' > "$T/bad.yaml"
out=$("$O" validate "$T/bad.yaml"); rc=$?
assert_eq 1 "$rc" "invalid 3.1 -> exit 1"
for p in "info.version kosong" "GET /a: tidak punya responses" "'b' harus diawali" "#/components/responses/Nope"; do
  assert_eq yes "$(printf '%s' "$out" | grep -qF -- "$p" && echo yes || echo no)" "reports: $p"
done
printf 'openapi: 2.5.0\ninfo: {title: x, version: "1"}\npaths: {/a: {get: {responses: {"200": {description: ok}}}}}\n' > "$T/v.yaml"
assert_exit 1 "unsupported openapi version" -- "$O" validate "$T/v.yaml"
printf 'openapi: 3.0.3\ninfo: {title: x, version: "1"}\npaths: {}\n' > "$T/empty.yaml"
assert_eq yes "$("$O" validate "$T/empty.yaml" | grep -q 'tidak ada endpoint' && echo yes || echo no)" "empty paths flagged (generator found no annotations)"
assert_exit 1 "diff refuses an invalid spec" -- "$O" diff "$T/contract.yaml" "$T/sw2.json"
echo '{"hello": 1}' > "$T/notapi.json"
assert_exit 2 "not OpenAPI at all" -- "$O" validate "$T/notapi.json"
echo '{bad json' > "$T/broken.json"
assert_exit 2 "broken JSON" -- "$O" validate "$T/broken.json"
assert_exit 2 "missing file" -- "$O" validate "$T/nope.yaml"
assert_exit 2 "usage" -- "$O" diff "$T/contract.yaml"
assert_exit 2 "usage bad flag" -- "$O" diff a b --nope x
exit $((FAILS > 0))
