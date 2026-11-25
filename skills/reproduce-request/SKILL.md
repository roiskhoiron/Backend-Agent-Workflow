---
name: reproduce-request
description: Skill internal Backend (pengganti /reproduce-device). Mereproduksi bug API dengan request ke server dev atau layanan lokal di slot worktree, membaca log dan isi database uji, lalu menulis bukti tekstual per langkah. Dipanggil oleh /validate-tiket, /audit-issue, dan HoE/Auditor; tidak dijalankan langsung oleh user.
user-invocable: false
---
Reproduksi bug Backend **tanpa layar**: request → response → log → data. Masukan dari pemanggil: KODE (atau slug audit), langkah reproduksi dari tiket, versi/ref yang dilaporkan, folder kerja, akun uji yang dijatahkan.

Baca dulu: `$AGENT_WORKFLOW_DIR/skills/_shared/environments.md`, `credentials.md`, `report-format.md` (→ Bukti tekstual).

## Langkah
1. **Pilih tempat reproduksi** (urutan):
   | Kondisi | Tempat |
   |---|---|
   | Versi yang dilaporkan sedang jalan di dev (cocokkan versi ter-deploy, `deploy-release.md`) | server **dev**, method apa pun, data berawalan KODE |
   | Bug di beta/live dan versi itu tidak ada di dev | server beta/live **hanya method aman** (`http-evidence.sh --safe`); bagian yang butuh menulis data → lokal |
   | Butuh menulis data di kondisi live, atau dev beda versi | **lokal**: layanan di `APP_PORT` slot, kode di ref versi itu (worktree tiket bila ada; di validasi/audit tanpa worktree → baca kode saja, reproduksi di dev) dengan `test-db.sh up` |
   Server bersama dipakai dalam kunci `deploy:<env>` milik orang lain? Request baca boleh; jangan menyimpulkan versi tanpa mencocokkan versi ter-deploy.
2. **Siapkan data** minimum untuk langkah tiket (akun uji dari `credentials.md`, data berawalan KODE). Butuh dua user (otorisasi) → dua akun, masing-masing dikunci.
3. **Kirim request** tiap langkah dengan `http-evidence.sh ... --label <TC/langkah> --note "<yang diharapkan>" --out <folder>/bukti.md`. Catat `request-id`/`trace-id` dari header response.
4. **Log**: ambil baris pada rentang waktu request (atau dengan request-id) dari sumber log di memory project; simpan potongan relevan ke `<folder>/log-<langkah>.txt`, tanpa token/PII.
5. **Data**: bila perilaku bergantung pada isi database, query baca-saja (database uji, atau dev) dan simpan hasilnya.
6. **Simpulkan** per langkah: **Tereproduksi** / **Tidak tereproduksi** / **Tertahan** (+ alasan, mis. butuh data live). Tidak tereproduksi setelah satu putaran → lapor ke pemanggil (HoE → Spesialis eskalasi), jangan menebak.
7. Tulis ringkasan ke `<folder>/<nama agen>.md`: tabel langkah → hasil → bukti (path), lalu blok bukti yang menandai bagian yang salah. Lepas kunci akun.

## Tidak boleh
- Menulis data di live; fuzzing di beta/live; database production dalam bentuk apa pun.
- Mengubah repo (reproduksi lokal hanya di worktree tiket yang sudah ada, tanpa commit).
- Menulis isi kredensial atau token di bukti.
