---
name: verify-provider
description: Skill internal Backend (pengganti /matrix-env di sisi pemakai). Sebagai penyedia contract - Schemathesis penuh terhadap spec OpenAPI di server dev, verifikasi Pact sebagai penyedia terhadap kontrak tiap klien, dan Matriks env endpoint tiket di dev/beta/live (method aman di beta/live). Dipanggil oleh /develop-tiket (Contract Runner langkah 2, QA langkah 6), /rilis-tiket, dan /branch-manager; tidak dijalankan langsung oleh user.
user-invocable: false
---
Mobile memeriksa **apakah** endpoint tersedia; Backend yang **membuatnya** tersedia, dimulai dari dev, dan membuktikan bahwa semua klien tetap dilayani. Masukan: KODE, endpoint tiket (dari contract di Acuan tiket), spec OpenAPI + versi, lokasi pact (folder/broker), base URL per env (memory project), env yang diminta, folder kerja.

## Langkah
1. **Matriks env** (awal pengerjaan, dan cek ulang sebelum deploy variant/rilis): tiap endpoint tiket × server.
   | Server | Cara cek |
   |---|---|
   | dev | Schemathesis endpoint tiket (setelah deploy tiket: penuh, lihat 2) |
   | beta, live | `http-evidence.sh --safe` / Schemathesis hanya GET/HEAD/OPTIONS; endpoint tulis → cek keberadaannya dari spec yang disajikan server atau respons method aman (mis. 405 vs 404); tidak bisa → **Tidak dicek** + alasan |
   Hasil: **Sesuai kontrak** / **Beda kontrak** / **Belum ada** / **Tidak dicek**. Untuk tiket Backend, **Belum ada** di dev sebelum pengerjaan itu wajar (tiket ini yang membuatnya); di beta/live sebelum rilis juga wajar. Yang penting: **Beda kontrak** pada endpoint yang sudah ada → lapor, bisa jadi bug atau drift.
2. **Schemathesis penuh di dev** (setelah `/deploy-service`, dalam kunci `deploy:dev` yang dipindah ke QA):
   `schemathesis run <spec> --url <base dev> --include-path-regex '<endpoint tiket>' --checks all` dengan header auth akun uji (dari env, bukan ditulis). Simpan output ke `<folder>/schemathesis-dev.txt`; tiap kegagalan → reproduksi dengan `http-evidence.sh` untuk bukti.
3. **Pact sebagai penyedia:** verifier project (memory project) terhadap pact semua klien yang menyentuh endpoint tiket (folder `pacts/` atau broker, versi klien yang masih didukung). Provider state disiapkan di database uji slot (layanan lokal di `APP_PORT`) atau dev. Hasil per klien: consumer → versi pact → Lulus/Gagal. Gagal pada klien yang masih didukung = **memutus** (`/check-compat`).
4. Tidak ada spec/pact → endpoint itu "tidak ada" + TC terkait **Tertahan**, tanya SPV (jawabannya jadi blok `## Catatan agen`).
5. Tulis `<folder>/matriks-env.md` (atau bagian Contract + Server di `uji.md`): perintah yang dijalankan, tabel endpoint × server, hasil Schemathesis, tabel Pact per klien. Lapor ke SPV: path + ringkasan ≤ 5 baris.

## Tidak boleh
- Fuzzing atau method tulis ke beta/live; data uji tanpa awalan KODE.
- Mengubah spec, pact, atau contract (perubahan contract → workflow produksi tiket).
- Menyimpulkan layak/selesai (itu SPV).
