# Alat (tools) + MCP

## Skrip `bin/`
Semua skrip dipanggil `"$AGENT_WORKFLOW_DIR/bin/<skrip>"`. Skrip yang memegang kunci diawali `AGENT_LOCK_PID=$PPID` di panggilan Bash yang sama.

| Skrip | Gunanya | Pakai | Exit |
| --- | --- | --- | --- |
| `lock.sh` | Kunci sumber daya bersama: `deploy:<env>`, `checkout:<path>`, `account:<kunci>`, `slot:<n>` | `acquire\|release\|who\|alive\|move <res> [owner [new-owner]]` | 0 ok; 1 dipegang pihak lain (stdout = pemilik); 2 salah pakai |
| `env-slot.sh` | Slot per worktree: `APP_PORT`, `DB_PORT`, port cadangan, nama database uji, `COMPOSE_PROJECT_NAME` | `acquire <worktree> <owner>`, `show <worktree>`, `release <worktree> <owner>`, `list` | 0 ok; 1 tidak ada slot bebas / belum punya slot; 2 salah pakai |
| `test-db.sh` | Database uji throwaway di container `agentdb-<slug>` (tmpfs, 127.0.0.1) | `up <worktree> <postgres\|mysql\|mariadb\|mongo> [image]`, `down <worktree>`, `status <worktree>` | 0 ok (cetak `DATABASE_URL`); 1 belum siap / tidak ada slot; 2 salah pakai |
| `migration-lint.sh` | Tandai migrasi yang menghapus/mengubah data (SQL + DSL ORM umum) | `migration-lint.sh <file>...` | 0 aman; 1 ada yang merusak data (berhenti dan tanya); 2 file tidak ada |
| `migration-check.sh` | Uji bolak-balik migrasi: skema awal → naik → turun → naik | `--up <cmd> --down <cmd> --schema <cmd> [--dir] [--out]` | 0 bisa dibatalkan; 1 langkah gagal / skema beda; 2 salah pakai / `DATABASE_URL` bukan lokal |
| `http-evidence.sh` | Satu request → blok bukti Markdown (request, response, durasi), rahasia disamarkan | `<METHOD> <URL> [-H ..] [-d ..] [--safe] [--label TC1] [--note ..] [--out file.md]` | 0 ada response (status apa pun); 1 gagal terhubung; 2 salah pakai / method tulis ditolak (`--safe`, host production) |
| `docs-publish.sh` | Platform dokumentasi `repo`: branch `agent-docs` di `origin` | `init <checkout>`, `put <docs-worktree> <path> <file> [pesan]`, `link <remote-url> <path>` | 0 ok (cetak path/link); 1 gagal git/kunci; 2 salah pakai |
| `release-trace.sh` | Tracing commit rilis → PR → tiket (TSV) | `<primary-ref> <protected-ref> <PREFIX>...` | 0 semua terlacak; 1 ada yang tak terlacak; 2 ref salah; 3 primary bukan leluhur protected |
| `manifest-check.sh` | Bandingkan kode tiket di `git log` dengan daftar tiket | `<base> <head> <KEY>...` | 0 sama; 1 beda; 2 salah pakai |
| `audit-mode.sh` | Nyalakan/matikan mode hanya-baca `/audit-issue` | `on\|off\|status` | 0 ok; 1 status off; 2 salah pakai |
| `housekeeping.sh` | Bersihkan container database uji yatim, image dangling, cache build lama | `housekeeping.sh` | 0 ok; 1 ada langkah gagal (di log) |

## Skill internal Backend
Tidak muncul di menu `/`; dipanggil oleh skill flow atau agen.

| Skill | Tugas | Dipanggil oleh |
| --- | --- | --- |
| `/reproduce-request` | Reproduksi bug lewat request + log + data (pengganti `/reproduce-device`) | `/validate-tiket`, `/audit-issue`, HoE, Auditor |
| `/check-compat` | Apakah perubahan merusak klien versi lama | `/develop-tiket` (rencana, review), `/rilis-tiket`, `/branch-manager` |
| `/write-migration` | Migrasi naik/turun + lint + uji bolak-balik | `/develop-tiket` langkah 3 (Coder) |
| `/test-integration` | Tes unit + integrasi di database uji slot, regresi area (pengganti `/test-device`) | `/develop-tiket` langkah 6 (QA), Coder |
| `/verify-provider` | Matriks env, Schemathesis, Pact sebagai penyedia (pengganti `/matrix-env`) | `/develop-tiket` langkah 2, 6, 7; `/rilis-tiket`; `/branch-manager` |
| `/deploy-service` | Deploy dev dalam kunci `deploy:dev` (pengganti `/build-app`) | `/develop-tiket` langkah 7 (Release) |
| `/deploy-variant` | Deploy beta; production hanya dengan izin (pengganti `/build-variant`) | `/develop-tiket` langkah 7, `/rilis-tiket`, `/branch-manager` |

## Alat luar
| Alat | Dipakai untuk |
| --- | --- |
| `docker` | database uji (`test-db.sh`), layanan pendukung per slot |
| `schemathesis` | uji spec OpenAPI: penuh di dev/lokal, method aman di beta/live |
| verifier Pact (`pact-provider-verifier` atau plugin framework) | verifikasi Backend sebagai penyedia terhadap pact klien |
| `oasdiff` | breaking change antar versi spec OpenAPI (`/check-compat`) |
| `jq`, `python3` | guard dan skrip |
| `gh` / `glab` | PR/MR GitHub / GitLab |
| `orca` | workspace, worktree, panel teammate |
| `graphify` | peta codebase untuk pertanyaan arsitektur (opsional) |

## MCP
| Konektor | Tool | Untuk |
| --- | --- | --- |
| **Atlassian** | `mcp__claude_ai_Atlassian__*` (`getJiraIssue`, `searchJiraIssuesUsingJql`, `addCommentToJiraIssue`, `transitionJiraIssue`, `getTransitionsForJiraIssue`, `atlassianUserInfo`) | baca tiket, komentar, transisi |
| **Claude Docs** | `mcp__claude_ai_Claude_Docs__*` (`batch`, `update`) | laporan bila platform dokumentasi = `claude-docs` |

## Pembersihan berkala
`housekeeping.sh` tidak dipasang otomatis. Jadwalkan sendiri, mis. tiap jam:
```bash
crontab -e
0 * * * * /path/ke/Backend-Agent-Workflow/bin/housekeeping.sh
```
(macOS juga bisa lewat launchd.) Log: `~/.agent-workflow/logs/housekeeping.log`.

| Dihapus | Tidak pernah dihapus |
| --- | --- |
| container `agentdb-*` berlabel `agent-workflow=1` yang worktree-nya hilang atau slotnya tidak dipegang lagi | container, volume, dan network tanpa label agen (milik kamu) |
| image dangling | image yang dipakai |
| cache build lebih tua dari 7 hari (dilewati saat ada build berjalan) | source, branch, data di server |

---
[← kembali ke README](../README.md)
