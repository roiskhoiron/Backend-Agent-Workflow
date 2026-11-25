---
name: deploy-variant
description: Skill internal Backend (pengganti /build-variant). Deploy ke beta setelah dev lulus, dan ke production hanya setelah izin eksplisit user per deploy, dengan cek ulang Matriks env server tujuan, migrasi, dan kompatibilitas klien. Dipanggil oleh /develop-tiket langkah 7, /rilis-tiket (QA minta env lain), dan /branch-manager (deploy live); tidak dijalankan langsung oleh user.
user-invocable: false
---
Masukan: KODE (atau versi rilis), env tujuan (`beta` / `production`), sumber (worktree tiket, atau worktree rilis `<repo>-rilis-vX.Y.Z` di `<sha-rilis>`), perintah deploy env itu (memory project).

Baca dulu: `$AGENT_WORKFLOW_DIR/skills/_shared/deploy-release.md`, `environments.md`, `rules.md` → Selalu berhenti dan tanya.

## Langkah
1. **Gerbang:**
   | Tujuan | Syarat sebelum deploy |
   |---|---|
   | beta | dev lulus (laporan uji tiket); Matriks env beta dicek ulang (`/verify-provider`, method aman) |
   | production | **izin eksplisit user untuk deploy ini** (tanya: versi, isi, migrasi yang ikut + siapa menjalankannya, klien yang menunggu, rencana balik); `/check-compat` tidak Memutus; deploy live memang dijalankan agen menurut memory project (bila milik manusia/pipeline → siapkan, lalu berhenti) |
   Syarat gagal → berhenti, lapor + saran.
2. **Migrasi:** tiket membawa migrasi → pastikan urutannya terhadap kode (memory project / rencana: sebelum atau sesudah deploy kode). Beta: ikut cara project. **Production: agen tidak menjalankan migrasi** (guard memblokir); minta manusia/pipeline menjalankannya pada urutan yang tertulis, tunggu konfirmasi.
3. **Kunci + deploy:** `lock.sh acquire deploy:<env> <KODE>-release1`, deploy dari sumber (`deploy-release.md`), cocokkan versi yang jalan, health check dengan `http-evidence.sh --safe` (live: selalu `--safe`).
4. **Uji di env itu:** beta → serahkan kunci ke QA (`lock.sh move`) untuk TC beta (menulis data hanya akun uji, awalan KODE). Production → hanya smoke baca-saja (`smoke-live`), lalu lepas kunci.
5. **Lapor:** env + base URL + versi, link job, hasil health/smoke. Komentar tiket (baris pertama link laporan) menyebut env + base URL + versi, tanpa kredensial.

## Tidak boleh
- Deploy production tanpa "ya" user untuk deploy ini (izin sebelumnya tidak berlaku ulang).
- Menjalankan migrasi production; menulis data di live.
- Deploy commit yang belum dilacak (`/branch-manager`: hanya `<sha-rilis>`).
