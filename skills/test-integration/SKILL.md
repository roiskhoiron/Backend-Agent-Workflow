---
name: test-integration
description: Skill internal Backend (pengganti /test-device). Menjalankan tes unit + integrasi project dengan database uji di container slot worktree, plus regresi area terdampak, lalu menulis hasil ke laporan uji. Dipanggil oleh /develop-tiket langkah 6 (QA) dan Coder sebelum lapor; tidak dijalankan langsung oleh user.
user-invocable: false
---
Masukan: KODE, worktree + slot env, base, TC dari rencana, perintah tes project (memory project → Perintah project), suite regresi (memory project → Suite regresi API), folder `${TMPDIR:-/tmp}/qa/<KODE>/`.

## Langkah
1. **Lingkungan:** `env-slot.sh show <worktree>` → `APP_PORT`, `DB_PORT`, `COMPOSE_PROJECT_NAME`. `test-db.sh up <worktree> <engine>` → `DATABASE_URL`. Layanan pendukung (redis, queue) di `SPARE_PORTS`, project compose dengan `COMPOSE_PROJECT_NAME` slot. Tidak pernah memakai database dev bersama untuk tes otomatis.
2. **Skema:** jalankan migrasi sampai terbaru di database uji (termasuk migrasi tiket).
3. **Tes project:** perintah tes unit + integrasi dengan env slot (`DATABASE_URL=… PORT=$APP_PORT <perintah tes>`). Simpan output ke `<folder>/tes.log`. Gagal → kembalikan ke Coder dengan nama tes + potongan error; flaky (lulus saat diulang sekali tanpa perubahan) → catat sebagai flaky, tetap laporkan.
4. **TC lokal:** TC rencana yang diuji di layanan lokal → jalankan layanan di `APP_PORT`, kirim request dengan `http-evidence.sh --label <TC>`, ambil log + query bukti (`environments.md`).
5. **Regresi area terdampak:** modul yang disentuh diff (`git diff --name-only <base>...HEAD`) → jalankan suite bertag `area-<modul>`; tidak ada yang cocok → tulis "tidak ada suite regresi untuk area ini". Gagal = sama dengan TC gagal.
6. **Suite tumbuh dari tiket:** tes TC yang lulus dan stabil disalin Coder ke folder suite (tag `area-<modul>`; `smoke-live` hanya bila baca saja), ikut direview di PR/MR tiket.
7. Tulis ke `<folder>/uji.md` (bagian Ringkasan, TC, Regresi area terdampak dari `report-format.md` → Laporan uji); output mentah di file terpisah. Lapor ke SPV: path + ringkasan Lulus/Gagal/Tertahan.

## Tidak boleh
- Tes ke database selain database uji slot; mematikan/melewati tes yang gagal supaya hijau.
- Port default project (bentrok dengan agen lain).
