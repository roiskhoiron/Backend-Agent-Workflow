---
name: write-migration
description: Skill internal Backend. Menulis migrasi database naik dan turun untuk satu tiket, memeriksa apakah merusak data, lalu mengujinya bolak-balik di database uji slot worktree. Dipanggil oleh /develop-tiket langkah 3 (Coder); tidak dijalankan langsung oleh user.
user-invocable: false
---
Migrasi ditulis **sebelum** kode yang memakainya, di branch tiket, oleh satu Coder per tiket. Masukan dari SPV: KODE, worktree + slot env, rencana migrasi (bagian Migrasi di rencana), perintah migrasi project (memory project → Perintah project: naik, turun, dump skema), engine database uji.

## Langkah
1. **Database uji:** `test-db.sh up <worktree> <engine>` (slot dari `env-slot.sh show <worktree>`); pakai `DATABASE_URL` keluarannya hanya di shell perintah migrasi. Jalankan migrasi yang sudah ada dulu sampai terbaru (keadaan base).
2. **Tulis migrasi** dengan generator/konvensi project (nama, folder, timestamp). Satu perubahan logis per file. Setiap migrasi **wajib punya turun** yang benar-benar membalik naiknya; framework tanpa turun (mis. hanya `up`) → tulis skrip balik terpisah dan sebut di rencana.
3. **Periksa merusak data:** `migration-lint.sh <file migrasi tiket>`.
   - Exit 0 → lanjut.
   - Exit 1 (hapus/ubah kolom/tabel, ganti nama, hapus/ubah data) → **berhenti, lapor ke SPV** dengan keluaran skrip. SPV bertanya ke user (`rules.md` → Selalu berhenti dan tanya). Klien masih membaca bentuk lama (`/check-compat`) → pola **tiga tahap**: tiket ini hanya menambah yang baru (+ backfill/dual-write bila perlu); penghapusan yang lama jadi tiket terpisah setelah klien pindah.
   - Migrasi besar di tabel besar (backfill, index pada tabel besar, ubah tipe) → catat risiko kunci tabel/durasi di rencana dan PR/MR; saran: index concurrent, backfill bertahap.
4. **Uji bolak-balik:**
   ```bash
   "$AGENT_WORKFLOW_DIR/bin/migration-check.sh" --dir <worktree> \
     --up "<perintah naik>" --down "<perintah turun khusus migrasi tiket>" --schema "<perintah dump skema>" \
     --out "${TMPDIR:-/tmp}/qa/<KODE>/migration-check"
   ```
   Semua `OK` → lanjut. `BEDA`/`GAGAL` → perbaiki migrasinya, ulangi. Migrasi data (skema sama) → tambah tes yang mengisi data contoh, menjalankan naik/turun, dan memeriksa isinya.
5. **Commit** file migrasi bersama tes/model yang memakainya (pesan menyebut KODE), push branch tiket.
6. **Lapor ke SPV:** file migrasi, hasil lint (dan persetujuan user bila ada), ringkasan `migration-check` (path laporan), durasi di database uji.

## Tidak boleh
- Menjalankan migrasi ke database selain database uji slot (dev/beta lewat deploy oleh Release; production tidak pernah, diblokir guard).
- Mengubah migrasi yang sudah ada di `<protected>` (sudah jalan di server lain): tulis migrasi baru.
- Melanjutkan migrasi yang merusak data tanpa persetujuan user.
