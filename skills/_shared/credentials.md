# Akun uji dan kredensial

Isi kredensial **tidak pernah** ditulis ke dokumen, platform tiket, PR/MR, commit, log laporan, atau `CLAUDE.md`. Di laporan cukup sebut nama kunci (mis. `QA_USER1`). Bukti HTTP memakai `http-evidence.sh`, yang menyamarkan header dan field rahasia.

## Urutan cari
1. `qa.env` di root project (template dari repo workflow ini)
2. `.env.test.local` / `.env.local` / `.env.*.local`
3. `.env` yang di-gitignore

Cek gitignore sebelum memakai file: `git check-ignore -q <file>`. File berisi kredensial **tidak** di-ignore → jangan dipakai, berhenti dan tanya (jangan commit, jangan tampilkan isinya).

## Belum ada kredensial
Berhenti dan tanya (`rules.md`) dengan saran:
1. Tambahkan `qa.env` ke `.gitignore` **lebih dulu**.
2. Salin template `$AGENT_WORKFLOW_DIR/templates/qa.env.example` ke root project sebagai `qa.env`.
3. User mengisi nilainya sendiri.

Kunci di template:
| Kunci | Isi |
|---|---|
| `QA_ENV` | `dev` atau `beta` |
| `QA_API_BASE_URL_DEV`, `QA_API_BASE_URL_BETA` | base URL API per env (tanpa kredensial) |
| `QA_USER1_LOGIN`, `QA_USER1_PASSWORD` | akun uji 1 (tambah `QA_USER2_…` untuk uji otorisasi antar-user) |
| `QA_ADMIN_LOGIN`, `QA_ADMIN_PASSWORD` | akun uji peran admin, bila ada |
| `QA_LIVE_USER_LOGIN`, `QA_LIVE_USER_PASSWORD` | opsional: akun uji khusus live untuk smoke baca-saja |

## Pemakaian
- Satu akun, satu agen, satu waktu: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" acquire account:QA_USER1 <owner>`, lepas setelah selesai.
- Kredensial dibaca saat dipakai (`set -a; . ./qa.env; set +a` di panggilan Bash yang sama, lalu login → token di variabel shell), tidak disalin ke file lain yang ter-track.
- Database uji lokal (`test-db.sh`) memakai nilai tetap `agent/agent`: bukan rahasia, hanya hidup di 127.0.0.1.

## Data uji
- Menulis data hanya di **database uji lokal**, **dev**, dan **beta**. Base URL atau `DATABASE_URL` mengarah ke production/live (cocok dengan `prod-hosts.txt` atau memory project) → berhenti.
- Semua data yang dibuat diawali kode tiket, mis. `PROJ-1234 Alamat Uji`, `proj1234+a@example.com`; regresi rilis memakai awalan versi `vX.Y.Z`.
- Catat data yang dibuat di bagian Temuan laporan (tanpa password).
