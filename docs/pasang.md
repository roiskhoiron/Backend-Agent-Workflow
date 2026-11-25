# Pasang di komputer lain (Linux / macOS)

1. **Prasyarat:** `git`, `jq`, `python3`, `docker`, `gh` dan/atau `glab`, Claude Code, Orca. Untuk uji contract: `schemathesis` (mis. `uv tool install schemathesis`), verifier Pact project, `oasdiff`. Mode tim: `/config` → Teammate mode → `auto`.
2. **Konektor claude.ai:** **Atlassian** (Jira); **Claude Docs** bila platform dokumentasi `claude-docs`.
3. **Login CLI:** `gh auth login` / `glab auth login`.
4. **Pasang dan cek:**
   ```bash
   git clone <url repo ini> ~/Backend-Agent-Workflow
   cd ~/Backend-Agent-Workflow && ./install.sh && bash tests/run.sh   # harus "ALL PASS"
   ```

Yang dibuat `install.sh` (idempoten, symlink: perubahan di repo langsung berlaku):
| Dari repo | Ke |
| --- | --- |
| `skills/<nama>/` | `~/.claude/skills/<nama>` |
| `skills/_shared/` | `~/.claude/skills/_backend-workflow-shared` |
| `agents/<peran>.md` | `~/.claude/agents/<peran>.md` |
| `hooks/guard.sh` | hook PreToolUse di `~/.claude/settings.json` (backup `settings.json.bak-agent-workflow`) |
| `templates/claude-global.md` | bagian di `~/.claude/CLAUDE.md` (sekali saja) |

> **Bentrok dengan workflow lain:** nama perintah dan agen sama dengan workflow Mobile (`/develop-tiket`, `coder`, …). `install.sh` **menolak** bila `~/.claude/skills/<nama>` atau `~/.claude/agents/<nama>.md` sudah symlink ke repo lain (mis. `mobiledev-agent-workflow`). Satu mesin = satu workflow, kecuali dipaksa dengan `--force` (menimpa yang lama).

## Per mesin (tidak ikut repo)
| File | Isi | Siapa |
| --- | --- | --- |
| `~/.agent-workflow/prod-hosts.txt` | host database production + API live, satu per baris | kamu ([Pagar keamanan](pagar-keamanan.md)) |
| `~/.agent-workflow/jira-transitions.json` | id transisi Todo / In Progress / Ready To Review per project | agen bertanya saat pertama jalan |
| `~/.agent-workflow/build-roots.txt` (opsional) | folder project tempat agen boleh menghapus artefak build | kamu |

## Per project
- **Syarat stack:** project harus bisa mengekspor spec OpenAPI 3.0/3.1 dari kode (anotasi Swagger / generator framework, contoh per stack di `skills/_shared/rules.md` → Syarat stack). Cek sekali: `bin/openapi-check.sh validate <spec hasil ekspor>` harus `OK`.
- **`qa.env`**: tambahkan `qa.env` ke `.gitignore` dulu, salin `templates/qa.env.example` ke root project sebagai `qa.env`, isi sendiri.
- **Memory project** (ditanya agen sekali, disimpan): branch `<primary>`/`<protected>` + strategi merge, base URL dev/beta/live + cara cek versi ter-deploy, perintah project (tes, migrasi naik/turun, dump skema, ekspor spec OpenAPI, jalankan lokal, deploy per env), engine database uji, lokasi spec OpenAPI + pact, klien + versi tertua yang didukung, pemilik migrasi production, platform dokumentasi (`repo`/`claude-docs`), suite regresi API, dokumen sumber.
- Blok `## Catatan agen` yang diberikan agen → kamu commit sendiri ke `CLAUDE.md` project.

---
[← kembali ke README](../README.md)
