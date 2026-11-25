#!/usr/bin/env bash
# Usage: http-evidence.sh <METHOD> <URL> [-H 'Name: value']... [-d <body|@file>] [--safe]
#                         [--label <TC1>] [--note <text>] [--out <file.md>] [--max-body <chars>]
# Sends one HTTP request and appends a Markdown evidence block (request, response, timing) to --out
# (default: stdout). This is the "bukti berupa teks" of Backend reports, replacing screenshots.
# Secrets never reach the evidence: Authorization/Cookie/Set-Cookie/X-Api-Key/... headers, secret-looking
# query params (token, key, signature, ...) and JSON fields (password, token, secret, ...) become [disamarkan].
# --safe: only GET/HEAD/OPTIONS (beta/live rule). Hosts listed in
# ${AGENT_WORKFLOW_STATE:-~/.agent-workflow}/prod-hosts.txt always get --safe.
# Exit: 0 a response came back (any status, it is recorded); 1 network error/timeout (recorded);
#       2 usage, or a write method refused by --safe / prod host.
exec python3 -I - "$@" <<'PY'
import json, os, re, sys, time, urllib.error, urllib.parse, urllib.request

SAFE = {"GET", "HEAD", "OPTIONS"}
SECRET_HDR = re.compile(r"^(authorization|proxy-authorization|cookie|set-cookie|x-api-key|api-key|x-auth-token|x-access-token|x-csrf-token|x-xsrf-token)$", re.I)
# substrings that are always secret, plus short words only as a whole part (so "author", "pinned" stay visible)
SECRET_KEY = re.compile(r"(pass(word)?|pwd|secret|token|api[-_]?key|apikey|credential|signature|session[-_]?id|private[-_]?key)|(^|[-_.])(auth|authorization|sig|otp|pin|cvv|key)($|[-_.])", re.I)
MASK = "[disamarkan]"

def die(msg, code=2):
    print(msg, file=sys.stderr); sys.exit(code)

a = sys.argv[1:]
if len(a) < 2 or a[0].startswith("-"):
    die("usage: http-evidence.sh <METHOD> <URL> [-H 'Name: value']... [-d <body|@file>] [--safe] [--label TC] [--note teks] [--out file.md] [--max-body n]")
method, url, rest = a[0].upper(), a[1], a[2:]
headers, data, safe, label, note, out, maxb = [], None, False, "", "", None, 4000
i = 0
while i < len(rest):
    o = rest[i]
    def nxt():
        if i + 1 >= len(rest): die(f"{o} butuh nilai")
        return rest[i + 1]
    if o in ("-H", "--header"): headers.append(nxt()); i += 2
    elif o in ("-d", "--data"): data = nxt(); i += 2
    elif o == "--safe": safe = True; i += 1
    elif o == "--label": label = nxt(); i += 2
    elif o == "--note": note = nxt(); i += 2
    elif o == "--out": out = nxt(); i += 2
    elif o == "--max-body": maxb = int(nxt()); i += 2
    else: die(f"argumen tidak dikenal: {o}")

u = urllib.parse.urlsplit(url)
if u.scheme not in ("http", "https") or not u.hostname:
    die(f"URL tidak valid: {url}")
prod_file = os.path.join(os.environ.get("AGENT_WORKFLOW_STATE") or os.path.expanduser("~/.agent-workflow"), "prod-hosts.txt")
prod = set()
if os.path.exists(prod_file):
    prod = {l.strip().lower() for l in open(prod_file) if l.strip() and not l.strip().startswith("#")}
host = u.hostname.lower()
is_prod = any(host == p or host.endswith("." + p) for p in prod)
if (safe or is_prod) and method not in SAFE:
    why = "host production (prod-hosts.txt)" if is_prod else "--safe"
    die(f"DITOLAK: {method} ke {host} tidak boleh ({why}); hanya GET/HEAD/OPTIONS tanpa menulis data")

def red_url(s):
    p = urllib.parse.urlsplit(s)
    q = [(k, MASK if SECRET_KEY.search(k) else v) for k, v in urllib.parse.parse_qsl(p.query, keep_blank_values=True)]
    return urllib.parse.urlunsplit(p._replace(query=urllib.parse.urlencode(q, safe="[]")))

def red_json(x):
    if isinstance(x, dict):
        return {k: (MASK if SECRET_KEY.search(str(k)) and not isinstance(v, (dict, list)) else red_json(v)) for k, v in x.items()}
    if isinstance(x, list):
        return [red_json(v) for v in x]
    return x

def red_body(raw, ctype):
    if not raw:
        return "", ""
    try:
        txt = raw.decode("utf-8")
    except UnicodeDecodeError:
        return f"<{len(raw)} byte biner>", ""
    try:
        return json.dumps(red_json(json.loads(txt)), indent=2, ensure_ascii=False), "json"
    except ValueError:
        pass
    if "x-www-form-urlencoded" in ctype:
        q = [(k, MASK if SECRET_KEY.search(k) else v) for k, v in urllib.parse.parse_qsl(txt, keep_blank_values=True)]
        return urllib.parse.urlencode(q, safe="[]"), ""
    return re.sub(r'(?i)("?(?:pass(?:word)?|secret|token|api[-_]?key)"?\s*[:=]\s*)("[^"]*"|\S+)', r"\1" + MASK, txt), ""

def cut(s):
    return s if len(s) <= maxb else s[:maxb] + f"\n… (dipotong, total {len(s)} karakter)"

def hdr_lines(pairs):
    return "\n".join(f"{k}: {MASK if SECRET_HDR.match(k) else v}" for k, v in pairs)

req_h = []
for h in headers:
    if ":" not in h: die(f"header tidak valid: {h}")
    k, v = h.split(":", 1); req_h.append((k.strip(), v.strip()))
body = None
if data is not None:
    body = open(data[1:], "rb").read() if data.startswith("@") else data.encode()
    if not any(k.lower() == "content-type" for k, _ in req_h):
        req_h.append(("Content-Type", "application/json"))

req = urllib.request.Request(url, data=body, method=method, headers=dict(req_h))
t0 = time.time(); status, rh, raw, err = None, [], b"", ""
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        status, rh, raw = r.status, list(r.getheaders()), r.read()
except urllib.error.HTTPError as e:
    status, rh, raw = e.code, list(e.headers.items()), e.read()
except Exception as e:  # network error, timeout, TLS
    err = f"{type(e).__name__}: {e}"
ms = int((time.time() - t0) * 1000)

ctype = next((v for k, v in req_h if k.lower() == "content-type"), "")
rctype = next((v for k, v in rh if k.lower() == "content-type"), "")
qb, qlang = red_body(body, ctype)
pb, plang = red_body(raw, rctype)
title = f"{label} — " if label else ""
md = [f"#### {title}{method} {u.path or '/'}", "",
      f"- Waktu: {time.strftime('%Y-%m-%d %H:%M:%S')} · durasi {ms} ms · host `{host}`"]
if note: md.append(f"- Catatan: {note}")
md += ["", "Request:", "```http", f"{method} {red_url(url)}"]
if req_h: md.append(hdr_lines(req_h))
if qb: md += ["", cut(qb)]
md += ["```", ""]
if err:
    md += [f"Response: **gagal terhubung** — `{err}`", ""]
else:
    md += [f"Response: **{status}**", "```http", hdr_lines(rh)]
    if pb: md += ["", cut(pb)]
    md += ["```", ""]
text = "\n".join(md) + "\n"
if out:
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    open(out, "a", encoding="utf-8").write(text)
    print(f"status={status if not err else 'error'} ms={ms} out={out}")
else:
    sys.stdout.write(text)
sys.exit(1 if err else 0)
PY
