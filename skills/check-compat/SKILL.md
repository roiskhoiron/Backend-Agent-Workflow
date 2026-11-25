---
name: check-compat
description: Skill internal Backend. Memeriksa apakah perubahan tiket merusak klien versi lama (aplikasi mobile yang sudah beredar, Frontend web) - breaking change di spec OpenAPI, perilaku endpoint, dan skema data yang dibaca klien. Dipanggil oleh /develop-tiket (Planner/SPV saat rencana, Reviewer saat review) dan /rilis-tiket; tidak dijalankan langsung oleh user.
user-invocable: false
---
Aplikasi mobile versi lama tidak bisa dipaksa memperbarui diri: endpoint yang dipakainya harus tetap bekerja. Masukan: KODE, worktree + base, spec OpenAPI (memory project → Contract), daftar klien + versi tertua yang didukung (memory project → Klien).

## Langkah
1. **Spec:** bandingkan spec di base dengan spec di branch tiket.
   - OpenAPI: `oasdiff breaking <(git show <base>:<spec>) <spec>` (tanpa oasdiff → diff manual: path/method dihapus, field response dihapus/diganti tipe, field request baru yang wajib, enum menyempit, kode status berubah, auth berubah).
   - Spec di repo katalog contract (workflow produksi tiket): bandingkan versi contract yang dipakai tiket dengan versi yang sedang dipakai klien.
2. **Perilaku tanpa perubahan spec:** baca diff kode endpoint yang disentuh: default berubah, validasi diperketat, urutan/pagination berubah, error code berubah, field jadi `null`. Ini sering lolos dari diff spec.
3. **Data:** migrasi tiket (`migration-lint.sh`) yang mengganti nama/menghapus kolom yang masih dibaca endpoint lama → memutus.
4. **Siapa yang terdampak:** klien mana memakai endpoint itu (pact klien di folder/broker, log akses per versi klien bila ada di memory project). Versi klien tertua yang didukung masih memanggilnya → terdampak.
5. **Putuskan:**
   | Hasil | Arti | Tindakan |
   |---|---|---|
   | **Aman** | hanya tambahan (endpoint/field opsional baru) | lanjut |
   | **Aman dengan catatan** | perubahan perilaku kecil yang klien lama toleransi | catat di rencana + PR/MR, TC regresi klien lama |
   | **Memutus** | klien yang masih didukung akan rusak | **berhenti dan tanya** (`rules.md`); saran: pecah tiga tahap (tambah baru → klien pindah → hapus lama) atau versi endpoint baru. Contract tidak diubah di workflow ini: perubahan contract → `/modify-epic-ticket` di workflow produksi tiket |
6. Tulis hasil ke rencana (bagian Kompatibilitas klien) dan ke PR/MR: tabel perubahan → jenis → klien terdampak → hasil. Tiap perubahan "Aman dengan catatan"/tahap tiga tahap jadi TC (request ala klien lama tetap lulus).

## Tidak boleh
- Menyatakan **Aman** tanpa membaca diff kode endpoint (langkah 2).
- Mengubah spec/contract untuk "menyesuaikan" kode.
