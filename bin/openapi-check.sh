#!/usr/bin/env bash
# Usage: openapi-check.sh validate <spec>                              -> is it standard OpenAPI 3.x?
#        openapi-check.sh diff <contract> <generated> [--paths <regex>] -> does the code's spec match the contract?
# Stack requirement (rules.md): whatever the backend stack, the project must GENERATE its OpenAPI spec from
# the code (swagger annotations / framework generator), with a command recorded in project memory.
# validate: openapi 3.0.x/3.1.x, info.title, info.version, paths; every operation has responses; every local
#   $ref resolves. Swagger 2.0 (swagger: "2.0") is refused: upgrade the generator or convert (swagger2openapi).
# diff: per endpoint (path x method) compares presence, response status codes, required request-body fields,
#   and top-level properties of JSON 2xx responses (local $ref resolved). Path params are normalised
#   (/orders/{id} == /orders/{orderId}). --paths limits the comparison to the ticket's endpoints.
#   Output: one line per difference: <kind> <METHOD> <path>: <detail>. For full breaking-change rules use oasdiff.
# Spec files: .json, or .yaml/.yml (PyYAML, else yq).
# Exit: 0 valid / same; 1 problems / differences (listed); 2 usage, unreadable file, or not OpenAPI at all.
cmd=${1:-}
case $cmd in
  validate) [ $# -eq 2 ] || { echo "usage: $0 validate <spec>" >&2; exit 2; } ;;
  diff) [ $# -eq 3 ] || { [ $# -eq 5 ] && [ "$4" = --paths ]; } || { echo "usage: $0 diff <contract> <generated> [--paths <regex>]" >&2; exit 2; } ;;
  *) echo "usage: $0 validate <spec> | diff <contract> <generated> [--paths <regex>]" >&2; exit 2 ;;
esac
exec python3 -I - "$@" <<'PY'
import json, re, shutil, subprocess, sys

def load(path):
    try:
        text = open(path, encoding="utf-8").read()
    except OSError as e:
        print(f"tidak bisa membaca {path}: {e.strerror}", file=sys.stderr); sys.exit(2)
    if text.lstrip().startswith("{"):
        try:
            return json.loads(text)
        except ValueError as e:
            print(f"{path}: JSON tidak valid: {e}", file=sys.stderr); sys.exit(2)
    try:
        import yaml
        return yaml.safe_load(text)
    except ImportError:
        if shutil.which("yq"):
            r = subprocess.run(["yq", "-o=json", ".", path], capture_output=True, text=True)
            if r.returncode == 0:
                return json.loads(r.stdout)
        print(f"{path}: YAML butuh PyYAML (pip install pyyaml) atau yq; atau ekspor spec sebagai JSON", file=sys.stderr); sys.exit(2)
    except Exception as e:
        print(f"{path}: YAML tidak valid: {e}", file=sys.stderr); sys.exit(2)

METHODS = ("get", "put", "post", "delete", "options", "head", "patch", "trace")

def resolve(spec, node, seen=()):
    """follow local $ref chains; returns (node, error)"""
    while isinstance(node, dict) and "$ref" in node:
        ref = node["$ref"]
        if not isinstance(ref, str) or not ref.startswith("#/"):
            return node, None  # external ref: not checked here
        if ref in seen:
            return node, None
        seen += (ref,)
        cur = spec
        for part in ref[2:].split("/"):
            part = part.replace("~1", "/").replace("~0", "~")
            if not isinstance(cur, dict) or part not in cur:
                return None, f"$ref tidak ditemukan: {ref}"
            cur = cur[part]
        node = cur
    return node, None

def all_refs(node):
    if isinstance(node, dict):
        for k, v in node.items():
            if k == "$ref" and isinstance(v, str):
                yield v
            else:
                yield from all_refs(v)
    elif isinstance(node, list):
        for v in node:
            yield from all_refs(v)

def validate(spec, name):
    probs = []
    if not isinstance(spec, dict):
        print(f"{name}: bukan dokumen OpenAPI", file=sys.stderr); sys.exit(2)
    if "swagger" in spec:
        probs.append(f"versi: Swagger {spec.get('swagger')} bukan OpenAPI 3.x; perbarui generator ke OpenAPI 3 atau konversi (swagger2openapi)")
        return probs
    ver = str(spec.get("openapi", ""))
    if not ver:
        print(f"{name}: tidak ada field 'openapi': bukan dokumen OpenAPI", file=sys.stderr); sys.exit(2)
    if not re.fullmatch(r"3\.(0|1)\.\d+", ver):
        probs.append(f"versi: openapi {ver} tidak didukung (harus 3.0.x atau 3.1.x)")
    info = spec.get("info") or {}
    for k in ("title", "version"):
        if not info.get(k):
            probs.append(f"info: info.{k} kosong")
    paths = spec.get("paths")
    if not isinstance(paths, dict) or (not paths and not spec.get("webhooks")):
        probs.append("paths: tidak ada endpoint (generator tidak menemukan anotasi?)")
        paths = {}
    for p, item in paths.items():
        if not p.startswith("/"):
            probs.append(f"paths: '{p}' harus diawali '/'")
        item, err = resolve(spec, item)
        if err: probs.append(f"ref {p}: {err}"); continue
        for m in METHODS:
            op = (item or {}).get(m)
            if op is None: continue
            if not isinstance(op, dict) or not op.get("responses"):
                probs.append(f"operasi {m.upper()} {p}: tidak punya responses")
    for ref in sorted(set(all_refs(spec))):
        if ref.startswith("#/"):
            _, err = resolve(spec, {"$ref": ref})
            if err: probs.append(f"ref: {err}")
    return probs

def norm(p):
    return re.sub(r"\{[^}]+\}", "{}", p.rstrip("/") or "/")

def ops(spec, only):
    out = {}
    for p, item in (spec.get("paths") or {}).items():
        if only and not re.search(only, p): continue
        item, _ = resolve(spec, item)
        for m in METHODS:
            op = (item or {}).get(m)
            if isinstance(op, dict):
                out[(m.upper(), norm(p))] = (p, op)
    return out

def json_schema(spec, holder):
    holder, _ = resolve(spec, holder)
    content = (holder or {}).get("content") or {}
    for ct, media in content.items():
        if "json" in ct:
            s, _ = resolve(spec, (media or {}).get("schema") or {})
            return s or {}
    return None

def props(spec, schema):
    """top-level property names (+required), merging allOf"""
    names, req = set(), set()
    schema, _ = resolve(spec, schema)
    if not isinstance(schema, dict): return names, req
    for sub in schema.get("allOf", []):
        n, r = props(spec, sub); names |= n; req |= r
    if schema.get("type") == "array" or "items" in schema:
        n, r = props(spec, schema.get("items") or {}); return n, r
    names |= set((schema.get("properties") or {}).keys())
    req |= set(schema.get("required") or [])
    return names, req

def diff(a, b, only):
    lines = []
    oa, ob = ops(a, only), ops(b, only)
    for key in sorted(set(oa) | set(ob)):
        m, _ = key
        if key not in ob:
            lines.append(f"hilang-di-kode {m} {oa[key][0]}: ada di contract, tidak ada di spec kode"); continue
        if key not in oa:
            lines.append(f"tidak-di-contract {m} {ob[key][0]}: ada di spec kode, tidak ada di contract"); continue
        pa, x = oa[key]; _, y = ob[key]
        ca, cb = set(map(str, x.get("responses") or {})), set(map(str, y.get("responses") or {}))
        if ca - cb: lines.append(f"status-hilang {m} {pa}: {', '.join(sorted(ca - cb))} ada di contract, tidak di kode")
        if cb - ca: lines.append(f"status-tambahan {m} {pa}: {', '.join(sorted(cb - ca))} tidak ada di contract")
        ra, rb = json_schema(a, x.get("requestBody") or {}), json_schema(b, y.get("requestBody") or {})
        if ra is not None or rb is not None:
            (na, qa), (nb, qb) = props(a, ra or {}), props(b, rb or {})
            if qa != qb: lines.append(f"request-wajib {m} {pa}: contract {sorted(qa)} vs kode {sorted(qb)}")
            if na - nb: lines.append(f"request-field-hilang {m} {pa}: {sorted(na - nb)}")
        for code in sorted(ca & cb):
            if not code.startswith("2"): continue
            sa = json_schema(a, (x.get("responses") or {}).get(code) or {})
            sb = json_schema(b, (y.get("responses") or {}).get(code) or {})
            if sa is None and sb is None: continue
            (na, _), (nb, _) = props(a, sa or {}), props(b, sb or {})
            if na - nb: lines.append(f"response-field-hilang {m} {pa} {code}: {sorted(na - nb)}")
            if nb - na: lines.append(f"response-field-tambahan {m} {pa} {code}: {sorted(nb - na)}")
    return lines

args = sys.argv[1:]
if args[0] == "validate":
    probs = validate(load(args[1]), args[1])
    for p in probs: print(p)
    if not probs: print("OK OpenAPI valid")
    sys.exit(1 if probs else 0)
only = args[4] if len(args) == 5 else None
a, b = load(args[1]), load(args[2])
bad = False
for spec, name in ((a, args[1]), (b, args[2])):
    for p in validate(spec, name):
        print(f"spec-tidak-valid {name}: {p}"); bad = True
if bad: sys.exit(1)
lines = diff(a, b, only)
for l in lines: print(l)
if not lines: print("OK spec kode sesuai contract")
sys.exit(1 if lines else 0)
PY
