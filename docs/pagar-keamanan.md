# Pagar keamanan

## Selalu diblokir oleh guard (`hooks/guard.sh`, juga di mode otonom)
| Pagar | Contoh yang diblokir |
| --- | --- |
| Push hanya ke `origin`; tidak force/hapus `main`/`master`/`develop` | `git push upstream fix/X`, `git push -f origin main` (tag `vX.Y.Z` eksplisit boleh ke `upstream`) |
| **Database production** | `psql`/`mysql`/`mongosh`/`pg_dump`/`redis-cli` atau alat migrasi yang menyebut host di `prod-hosts.txt` |
| **Migrasi dengan env production** | `NODE_ENV=production npx knex migrate:latest`, `RAILS_ENV=production rails db:migrate`, `artisan migrate --env=production` |
| **Menulis data ke host production lewat HTTP** | `curl -X POST https://api.live...`, `curl -d ...`, `http PUT ...` ke host di `prod-hosts.txt` |
| **Data Docker milik user** | `docker system prune`, `docker volume prune`, `docker rm mydb`, `docker volume rm pgdata`, `docker compose down -v` (selain project `agent-*`) |
| `rm -r` di luar project | kecuali artefak build (`node_modules`, `target`, `dist`, `build`, `.venv`, …) di worktree lain repo yang sama, dan isi `${TMPDIR:-/tmp}/{qa,validate,audit}` |
| Transisi Jira | status di luar `~/.agent-workflow/jira-transitions.json` (Done tidak pernah ada) |
| Worktree & Orca | edit di worktree primary; tab/workspace/project Orca baru; `git worktree remove --force` |
| Mode audit | semua penulisan ke repo, Jira, git remote; `docker run/rm/compose up`; `test-db.sh`, `migration-check.sh`, `docs-publish.sh`, `env-slot.sh` (kecuali `test-db.sh status`, `env-slot.sh show\|list`, `docs-publish.sh link`) |

### `prod-hosts.txt`
`~/.agent-workflow/prod-hosts.txt` diisi **kamu**, satu host per baris (database production, API live, replika); subdomain ikut cocok, `#` untuk komentar.
```text
# production
db.prod.example.com
api.example.com
```
Tanpa file ini guard hanya mengenali penanda env production (`NODE_ENV=production`, `--env=production`, …).

### Batas guard
Guard hanya membaca **teks perintah**. URL production yang tersembunyi di `.env` atau variabel tidak terlihat. Karena itu:
- aturan di `rules.md` tetap berlaku walau guard diam;
- `test-db.sh` hanya membuat database di 127.0.0.1, `migration-check.sh` menolak `DATABASE_URL` yang bukan lokal, `http-evidence.sh` memaksa `--safe` untuk host production;
- mode audit tidak menangkap tulis lewat shell (`sed -i`, `>`).

## Dijaga aturan skill (bukan guard)
- Merge PR rilis ke `<primary>`: hanya manusia. Merge PR tiket hanya setelah audit + "ya".
- Deploy production: izin eksplisit **per deploy**.
- Uji di server dev/beta hanya sambil memegang kunci `deploy:<env>`.

## Agen selalu berhenti dan bertanya bila
1. Deploy production.
2. Migrasi menghapus atau mengubah data (`migration-lint.sh` exit 1).
3. Perubahan memutus kompatibilitas klien lama (`/check-compat` → Memutus).
4. Contract tidak bisa dipenuhi (→ `/modify-epic-ticket` di workflow produksi tiket).
5. Hotfix (sementara manual).
6. Kredensial tidak ada atau mengarah ke production.
7. Dua fix hotfix bentrok.
8. Kunci `deploy:<env>` dipegang tiket Jira lain.

**Kredensial** dibaca dari `qa.env` lokal yang di-gitignore dan tidak pernah ditulis ke dokumen, Jira, atau MR; bukti HTTP otomatis menyamarkan header/field rahasia. Data uji berawalan kode tiket (rilis: `vX.Y.Z`). Live hanya method aman.

---
[← kembali ke README](../README.md)
