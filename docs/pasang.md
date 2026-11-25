# Pasang di komputer lain (Linux / macOS)

1. **Prasyarat:** `git`, `jq`, `python3`, `docker`, `gh` dan/atau `glab`, dan minimal satu AI coding agent (Claude Code, Codex CLI, Gemini CLI, Cursor, atau agent lain yang membaca `AGENTS.md`). Orca opsional (workspace + panel teammate di Claude Code). Untuk uji contract: `schemathesis` (mis. `uv tool install schemathesis`), verifier Pact project, `oasdiff`. Mode tim (hanya Claude Code): `/config` → Teammate mode → `auto`.
2. **Konektor:** Atlassian hanya bila platform tiket = Jira (di agent selain Claude Code: server MCP Atlassian milik agent itu); GitHub/GitLab cukup `gh`/`glab` yang sudah login. Claude Docs hanya bila platform dokumentasi `claude-docs`.
3. **Pasang dan cek:**
   ```bash
   git clone <url repo ini> ~/Backend-Agent-Workflow
   cd ~/Backend-Agent-Workflow
   ./install.sh                 # menu: agent + cakupan
   bash tests/run.sh            # harus "ALL PASS"
   ```
   Tanpa menu: `./install.sh --agent <claude,codex,gemini,cursor,generic> --scope <global|project> [--project DIR] [--force]`.

Yang dibuat `install.sh` (symlink ke repo ini: `git pull` di repo = semua agent langsung memakai versi baru; idempoten; file pengaturan dicadangkan sekali sebagai `<file>.bak-backend-workflow`):

| Agent | Skill | Instruksi (berisi `AGENT_WORKFLOW_DIR`) | Pagar (`hooks/guard.sh`) |
| --- | --- | --- | --- |
| `claude` | global `~/.claude/skills/` · project `.claude/skills/`; peran → `.claude/agents/` | `~/.claude/CLAUDE.md` · `CLAUDE.md` | `PreToolUse` di `.claude/settings.json` |
| `codex` | `~/.agents/skills/` · `.agents/skills/` | `~/.codex/AGENTS.md` · `AGENTS.md` | `PreToolUse` (matcher `Bash`) di `~/.codex/hooks.json` · `.codex/hooks.json`; **trust dulu di Codex** |
| `gemini` | `~/.agents/skills/` · `.agents/skills/` | `~/.gemini/GEMINI.md` · `GEMINI.md` | `BeforeTool` (`run_shell_command\|write_file\|replace`) di `.gemini/settings.json` |
| `cursor` | `~/.cursor/skills/` · `.cursor/skills/` | project: `AGENTS.md`; global: tambahkan sendiri di Cursor Settings → Rules | `beforeShellExecution` di `.cursor/hooks.json` |
| `generic` | `~/.agents/skills/` · `.agents/skills/` | project: `AGENTS.md`; global: tidak ada lokasi standar | tidak ada (hanya aturan) |

- Instruksi ditulis di antara penanda `<!-- backend-agent-workflow:start -->` … `end`; isi lain file itu tidak disentuh, dan pemasangan ulang hanya mengganti blok itu.
- Satu `guard.sh` untuk semua agent: ia mengenali format input Claude Code/Codex, Gemini CLI, dan Cursor, dan semuanya memblokir dengan exit code 2.
- Agent selain Claude Code tidak punya teammate: `--tim` = `--solo`, file `agents/<peran>.md` dipakai sebagai daftar tugas per peran.
- Konvensi path agent lain (Codex, Gemini, Cursor) diambil dari dokumentasi resmi per November 2026; Gemini CLI kini digantikan Antigravity CLI, sehingga jalurnya bisa berubah.

> **Bentrok dengan workflow lain:** nama perintah dan agen sama dengan workflow Mobile (`/develop-tiket`, `coder`, …). `install.sh` **menolak** bila folder skill/agen sudah symlink ke repo lain (mis. `mobiledev-agent-workflow`). Satu agent + cakupan = satu workflow, kecuali dipaksa dengan `--force`.

## Per mesin (tidak ikut repo)
| File | Isi | Siapa |
| --- | --- | --- |
| `~/.agent-workflow/prod-hosts.txt` | host database production + API live, satu per baris | kamu ([Pagar keamanan](pagar-keamanan.md)) |
| `~/.agent-workflow/board-transitions.json` | status Todo / In Progress / Ready To Review per board (GitHub/GitLab/Jira) | agen bertanya saat pertama jalan |
| `~/.agent-workflow/projects/<repo>/memory.md` | memory project untuk agent selain Claude Code | agen |
| `~/.agent-workflow/build-roots.txt` (opsional) | folder project tempat agen boleh menghapus artefak build | kamu |

## Per project
- **Syarat stack:** project harus bisa mengekspor spec OpenAPI 3.0/3.1 dari kode (anotasi Swagger / generator framework, contoh per stack di `skills/_shared/rules.md` → Syarat stack). Cek sekali: `bin/openapi-check.sh validate <spec hasil ekspor>` harus `OK`.
- **`qa.env`**: tambahkan `qa.env` ke `.gitignore` dulu, salin `templates/qa.env.example` ke root project sebagai `qa.env`, isi sendiri.
- **Memory project** (ditanya agen sekali, disimpan): branch `<primary>`/`<protected>` + strategi merge, base URL dev/beta/live + cara cek versi ter-deploy, perintah project (tes, migrasi naik/turun, dump skema, ekspor spec OpenAPI, jalankan lokal, deploy per env), engine database uji, lokasi spec OpenAPI + pact, klien + versi tertua yang didukung, pemilik migrasi production, platform dokumentasi (`repo`/`claude-docs`), suite regresi API, dokumen sumber.
- Blok `## Catatan agen` yang diberikan agen → kamu commit sendiri ke `CLAUDE.md` project.

---
[← kembali ke README](../README.md)
