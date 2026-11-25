# Lingkungan uji Backend

Pengganti "Device, akun uji, nomor build" di workflow Mobile. Tidak ada layar: bug direproduksi dan fitur diuji lewat **request ke API + log + isi database uji**. Sumber daya bersama yang harus dibagi: **port dan database uji** (satu per worktree) dan **server dev/beta** (satu deploy pada satu waktu).

**Wajib:** setiap panggilan `lock.sh`/`env-slot.sh` diawali `AGENT_LOCK_PID=$PPID` di panggilan Bash yang sama. Tiap panggilan Bash = shell baru; `$PPID` di situ = proses Claude Code yang hidup selama agen hidup. Tanpa itu kunci dianggap basi dan bisa direbut agen lain.

## Slot env per worktree
```bash
AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/env-slot.sh" acquire <worktree> <KODE>-spv1
# SLOT=3  APP_PORT=18030  DB_PORT=18031  SPARE_PORTS=18032-18039
# DB_NAME=agent_svc_12  DB_CONTAINER=agentdb-svc-12  COMPOSE_PROJECT_NAME=agent-svc-12
```
- SPV mengambil slot sekali per worktree tiket; agen lain di worktree itu membaca nilainya dengan `env-slot.sh show <worktree>` (tanpa mengambil ulang).
- Layanan lokal dijalankan di `APP_PORT`, layanan pendukung (redis, queue, mock) di `SPARE_PORTS`, dengan `COMPOSE_PROJECT_NAME` dari slot bila project memakai compose. Jangan pakai port default project (3000, 8000, 8080, 5432): agen paralel akan bentrok.
- Slot dianggap bebas begitu proses pemegangnya mati; `housekeeping.sh` membuang container database uji yang slotnya sudah tidak dipegang.
- `env-slot.sh` exit 1 (tidak ada slot bebas) → tunggu worktree lain selesai, atau tanya user.

## Database uji
```bash
"$AGENT_WORKFLOW_DIR/bin/test-db.sh" up <worktree> <postgres|mysql|mariadb|mongo> [image]
# DATABASE_URL=postgresql://agent:agent@127.0.0.1:18031/agent_svc_12
```
- Engine + image dari memory project (Database uji); samakan versi mayor dengan production.
- Container `agentdb-<slug>`, data di tmpfs: cepat dan selalu bersih saat dibuat ulang. `test-db.sh down <worktree>` setelah tiket Ready To Review.
- Isi `DATABASE_URL` (atau variabel yang dipakai project) **hanya di shell perintah itu** atau di `.env.local` worktree yang di-gitignore; jangan mengubah `.env` yang ter-track.
- Tes integrasi, migrasi, dan reproduksi lokal **selalu** ke database uji ini. Database dev bersama hanya dibaca, kecuali TC yang memang butuh data di server dev (data berawalan kode tiket).

## Server bersama (dev, beta)
Server dev dan beta dipakai semua tiket. Deploy tiket A menimpa kode tiket B, jadi **deploy + uji di server itu = satu kunci**:
```bash
AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" acquire deploy:dev <KODE>-release1
```
- Release mengambil kunci `deploy:<env>` sebelum deploy, lalu **memindahkannya** ke QA (`lock.sh move deploy:dev <KODE>-release1 <KODE>-qa1`) yang menguji di server itu, dan QA melepasnya setelah uji selesai. Tanpa kunci → jangan uji di server bersama: hasilnya bisa milik tiket lain.
- Sebelum menguji, cocokkan versi yang ter-deploy (cara dari memory project → Server per env, mis. `GET /version` = hash commit tiket). Beda → deploy tertimpa: lapor ke SPV, jangan dianggap gagal tiket.
- `--batch`: satu deploy branch batch untuk semua tiket, satu pemegang kunci untuk seluruh QA batch.

**Kunci dipakai** (`acquire` exit 1, stdout = pemilik `<KODE>-<peran><n>`):
- Pemilik dari batch/rilis yang sama → antre: coba lagi tiap 30 detik, tanpa bertanya.
- Pemilik **tiket lain** → **tanya user** (juga di mode otonom; teammate lewat SPV): "Server **dev** sedang dipakai **<KODE> — <judul>** (deploy + uji). Tugas kita: **<KODE> — <judul>**. Tunggu atau dahulukan?" **Tunggu** → antre. **Dahulukan** → minta user menghubungi pemiliknya; agen tidak merebut kunci orang lain. Pemilik `human-*` (user sedang menguji manual) diperlakukan sama.
- Kunci milik proses yang sudah mati otomatis dianggap bebas.

## Reproduksi dan bukti: request + log
```bash
"$AGENT_WORKFLOW_DIR/bin/http-evidence.sh" GET "$BASE/v1/orders/123" -H "Authorization: Bearer $TOKEN" \
  --label TC1 --note "AC1: pesanan milik user lain ditolak" --out "${TMPDIR:-/tmp}/qa/PROJ-12/uji.md"
```
- Tiap TC = satu atau beberapa blok bukti: request, response (status, header, body), durasi. Header dan field rahasia otomatis `[disamarkan]`; token diambil dari env saat dipakai, tidak pernah ditulis.
- Beta/live: tambahkan `--safe` (hanya GET/HEAD/OPTIONS). Host di `prod-hosts.txt` selalu `--safe`.
- **Log:** ambil potongan log yang relevan (rentang waktu request, `request-id`/`trace-id` dari header response) dari sumber log di memory project (log lokal layanan, `docker logs`, `kubectl logs`, dashboard). Cukup baris yang membuktikan, tanpa token/PII; tandai baris yang salah dengan `<<< di sini`.
- **Database:** hasil query di database uji (atau baca-saja di dev) yang membuktikan keadaan data, dalam blok kode.
- Bagian yang salah ditandai di laporan: kutip field/baris dan beri label TC/AC, mis. `AC2: status harus 403, didapat 200`.

## Alat uji
| Kebutuhan | Alat | Catatan |
|---|---|---|
| Unit + integrasi | perintah tes project (memory project) dengan `DATABASE_URL` slot | `/test-integration` |
| Contract penuh di dev | `schemathesis run <spec> --url <base dev> --include-path <endpoint tiket>` | dev saja; fuzzing & menulis data |
| Contract di beta/live | Schemathesis hanya `--include-method GET --include-method HEAD --include-method OPTIONS`, tanpa fuzzing berat | `--safe` di http-evidence |
| Pact sebagai penyedia | verifier Pact project (`pact-provider-verifier`, plugin framework) terhadap pact klien dari folder/broker | `/verify-provider` |
| Spec dari kode | perintah ekspor spec (memory project) → `openapi-check.sh validate`, lalu `openapi-check.sh diff <contract> <spec kode> --paths <endpoint tiket>` | `/develop-tiket` langkah 4–6 |
| Breaking change contract | `oasdiff breaking <spec kode base> <spec kode tiket>` (OpenAPI) | `/check-compat` |
| Migrasi | `migration-lint.sh`, `migration-check.sh` | `/write-migration` |
| Bukti HTTP | `http-evidence.sh` | semua laporan |

Alat tidak terpasang → catat "tidak bisa dicek" + alasan, TC terkait **Tertahan**; tanya user bila memblokir keputusan. Jangan memasang alat global tanpa izin.

## Akun uji
Satu akun uji satu agen satu waktu: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" acquire account:qa.user1 <KODE>-qa1` (exit 1 = dipakai agen lain, stdout = pemiliknya). Detail: `credentials.md`.

## Folder kerja
File sementara (bukti, log, output alat) **tidak** ditulis ke repo:
- Validator & tim validasi: `${TMPDIR:-/tmp}/validate/<KODE>/`
- QA, Contract Runner (develop): `${TMPDIR:-/tmp}/qa/<KODE>/`
- Audit: `${TMPDIR:-/tmp}/audit/<slug>/`
