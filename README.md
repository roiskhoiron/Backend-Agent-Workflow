# backend-agent-workflow

Tim agen Claude Code + Orca untuk mengerjakan tiket Jira di proyek **Backend**: dari cek tiket, migrasi database, kode, uji integrasi + contract, deploy dev/beta, sampai PR/MR dan rilis. Kerangkanya sama dengan [mobiledev-agent-workflow](https://github.com/roiskhoiron/mobiledev-agent-workflow) (empat perintah, tim agen, worktree), dengan tiga perbedaan pokok: **tidak ada layar** untuk diuji, **ada migrasi database**, dan Backend adalah **penyedia contract** yang dipakai Mobile dan Frontend web. Tiket masuk dari [workflow produksi tiket](https://github.com/roiskhoiron/sdd-agent-workflow) (atau ditulis manual); memindahkan tiket ke **Done** tetap tugas manusia.

Status: **v1 kerangka terpasang**, belum diuji di tiket nyata. Stack project (bahasa, framework, database) dibaca dari memory project, bukan ditulis di sini.

## Daftar isi
1. [Mulai cepat](#mulai-cepat) dan [istilah penting](#istilah-penting) (di halaman ini)
2. [Alur kerja + papan kanban](docs/alur-kerja.md): `/validate-tiket`, `/develop-tiket`, `/rilis-tiket`, `/branch-manager`, `/audit-issue`
3. [Tim agen](docs/tim-agen.md): peran, nama, model
4. [Pagar keamanan](docs/pagar-keamanan.md): yang diblokir guard (termasuk database production), kapan agen berhenti dan bertanya
5. [Alat (tools) + MCP](docs/alat.md): skrip `bin/`, skill internal Backend, alat uji, pembersihan otomatis
6. [Pasang di komputer lain](docs/pasang.md)
7. [Masalah umum](docs/masalah-umum.md)
8. [Rancangan dan keputusan implementasi](docs/design-summary.md)
9. [Isi repo](#isi-repo) dan [merawat dokumen](#merawat-dokumen-ini) (di halaman ini)

## Mulai cepat

```bash
git clone <repo ini> && cd backend-agent-workflow && ./install.sh
bash tests/run.sh   # semua tes skrip + guard
```

Lalu ketik di Claude Code, di dalam terminal Orca:

| Perintah | Gunanya | Jalankan dari |
| --- | --- | --- |
| `/validate-tiket KODE... [--solo\|--tim]` | Cek tiket layak dikerjakan; bug direproduksi lewat request API dan log. `--tim`: PdM, Contract Runner, HoE, PjM (+ Spesialis eskalasi). Hasil: laporan berisi bukti request/response + komentar Jira | mana saja |
| `/develop-tiket KODE... [--solo\|--tim] [--batch\|--separate]` | Rencana, migrasi naik/turun, kode (TDD), review, uji integrasi + Schemathesis + Pact penyedia, deploy dev (+ beta), PR/MR, komentar Jira, tiket ke Ready To Review | workspace domain |
| `/rilis-tiket KODE...` | Tindak lanjut feedback QA per tiket: kembalikan ke Todo, deploy ke env lain (beta; production dengan izin), atau audit + merge PR/MR tiket | root project atau domain |
| `/branch-manager --rilis KODE` | Rilis per versi: tracing perubahan, migrasi + kompatibilitas klien dalam rilis, regresi penuh di beta, laporan rilis, PR rilis, tag setelah PR rilis di-merge manusia, deploy live (izin/pipeline) + smoke live | root project atau domain |
| `/audit-issue "teks" [--solo\|--tim] [lampiran...]` | Telusuri keluhan yang belum jadi tiket, **hanya-baca**. Hasil: laporan + saran tiket | mana saja |

Contoh:
```text
/validate-tiket API-1234
/develop-tiket API-1234 API-1240 --tim
/develop-tiket API-1300 --solo --separate
/audit-issue "checkout kadang 500 setelah update v2.3" --solo
/rilis-tiket API-1234
/branch-manager --rilis API-1400
```

Skill internal khas Backend dipanggil oleh perintah di atas, tidak diketik sendiri: `/reproduce-request`, `/check-compat`, `/write-migration`, `/test-integration`, `/verify-provider`, `/deploy-service`, `/deploy-variant` ([docs/alat.md](docs/alat.md)).

## Istilah penting

| Istilah | Penjelasan sederhana |
| --- | --- |
| **SPV** | Agen "mandor": membaca tiket, membagi tugas, memutuskan tiket selesai |
| **Workspace domain** | Workspace Orca yang kamu buka untuk kerja kode. Root project hanya untuk audit, tanya, dan rilis |
| **Worktree tiket** | Salinan kerja repo khusus satu tiket, folder `<repo>-<nomor>` di sebelah checkout domain |
| **Slot env** | Jatah port layanan + database uji (container) untuk satu worktree, supaya agen paralel tidak bentrok. Pengganti "jatah device" di Mobile |
| **Database uji** | Database sekali pakai di container (`agentdb-<worktree>`), satu per worktree; satu-satunya database yang boleh ditulis tes dan migrasi |
| **Kunci `deploy:<env>`** | Server dev/beta dipakai bersama: deploy + uji di sana satu tiket pada satu waktu |
| **Contract** | Spec OpenAPI yang disepakati Backend dan klien. Backend = penyedia; perubahan contract lewat workflow produksi tiket (`/modify-epic-ticket`), bukan di sini |
| **Kompatibilitas klien** | Aplikasi mobile versi lama tidak bisa dipaksa update: perubahan yang memutusnya dipecah tiga tahap (tambah baru → klien pindah → hapus lama) |
| **Migrasi naik/turun** | Perubahan skema database dan kebalikannya; diuji bolak-balik di database uji. Migrasi production dijalankan manusia atau pipeline |
| **Bukti tekstual** | Request, response, potongan log, hasil query (rahasia disamarkan). Pengganti screenshot bertanda |
| **Platform dokumentasi** | Tempat laporan: default Markdown di branch `agent-docs` (`repo`), atau Claude Docs |
| **Guard** | Hook yang memblokir perintah berbahaya sebelum dijalankan |
| **Downstream / upstream** | `origin` = fork kita (boleh push branch); `upstream` = repo utama (hanya lewat PR/MR) |
| **TC / AC** | Test case / acceptance criteria tiket. Hasil TC: Lulus, Gagal, atau Tertahan (dengan alasan) |

## Isi repo

| Folder | Isi |
| --- | --- |
| `skills/<perintah>/SKILL.md` | Langkah tiap perintah (5 skill flow) dan 7 skill internal Backend |
| `skills/_shared/` | Aturan bersama: `rules.md` (tim, guard, git, worktree, memory project), `environments.md` (slot env, database uji, server bersama, alat uji), `credentials.md`, `deploy-release.md`, `report-format.md` |
| `agents/` | Peran agen (model, tugas, larangan) |
| `bin/` | Skrip pembantu (tabel di [docs/alat.md](docs/alat.md)) |
| `hooks/guard.sh` | Pagar keamanan |
| `templates/` | `qa.env.example` (akun uji), bagian `CLAUDE.md` global |
| `tests/` | Tes skrip & guard: `bash tests/run.sh` |
| `docs/` | Panduan lengkap dan ringkasan rancangan |

## Merawat dokumen ini

README + folder `docs/` adalah pintu masuk untuk pemula. README tetap singkat; detail ada di `docs/<topik>.md`. **Setiap perubahan workflow atau alat wajib memperbarui README atau halaman `docs/` yang sesuai di commit yang sama.** `tests/readme_test.sh` gagal bila ada perintah, skill internal, skrip `bin/`, atau MCP yang belum disebut di README maupun `docs/*.md`. Detail teknis tetap di `skills/` dan `agents/`.
