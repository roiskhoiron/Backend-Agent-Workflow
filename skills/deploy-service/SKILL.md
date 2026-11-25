---
name: deploy-service
description: Skill internal Backend (pengganti /build-app). Deploy layanan dari branch tiket atau branch batch ke server dev dalam kunci deploy:dev, mencocokkan versi yang jalan, lalu menyerahkan kunci ke QA. Dipanggil oleh /develop-tiket langkah 7 (Release); tidak dijalankan langsung oleh user.
user-invocable: false
---
Masukan dari SPV: KODE (atau daftar KODE batch), sumber (`--batch`: checkout domain di branch batch; `--separate`: worktree tiket), perintah deploy dev (memory project → Perintah project), cara cek versi (memory project → Server per env), nama QA penerima kunci.

Baca dulu: `~/.claude/skills/_backend-workflow-shared/deploy-release.md`, `environments.md` → Server bersama.

## Langkah
1. **Kunci server:** `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" acquire deploy:dev <KODE>-release1`. Exit 1 → ikuti "Kunci dipakai" (`environments.md`); tiket lain → lewat SPV tanya user.
2. **Pastikan sumbernya benar:** commit yang di-deploy = HEAD sumber yang sudah di-push (`git -C <sumber> status --porcelain` kosong; `--separate`: `git log @{u}..` kosong). Catat `<branch>@<sha7>`.
3. **Deploy** dengan perintah dari memory project, dijalankan dari sumber itu. Pipeline CI (deploy dari branch) → picu sesuai cara project, tunggu selesai, simpan link job. Migrasi dev ikut cara project (pipeline atau perintah migrasi dev dari memory project); tidak pernah ke production.
4. **Cocokkan versi:** cek versi yang jalan di dev (maks. ±5 menit menunggu). Tidak cocok → lepas kunci, lapor ke SPV (deploy gagal/tertimpa), jangan serahkan ke QA.
5. **Health check:** `http-evidence.sh GET <base dev>/<health> --label deploy --out ${TMPDIR:-/tmp}/qa/<KODE>/deploy.md` (endpoint health dari memory project; tidak ada → endpoint GET tiket).
6. **Serahkan kunci ke QA** tanpa celah: `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" move deploy:dev <KODE>-release1 <KODE>-qa1`. QA yang melepasnya setelah uji dev selesai.
7. **Lapor ke SPV:** env + base URL + versi (`<branch>@<sha7>`), link job deploy, hasil health check.

Deploy gagal/dibatalkan → lepas `deploy:dev` (`release deploy:dev <KODE>-release1`) sebelum lapor.

## Tidak boleh
- Deploy tanpa kunci `deploy:dev`; deploy dari kode yang belum di-push.
- Deploy ke beta/production (itu `/deploy-variant`, production hanya dengan izin).
- Menulis kredensial deploy di laporan, PR/MR, atau tiket.
