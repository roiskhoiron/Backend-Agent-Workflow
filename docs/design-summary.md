# Ringkasan rancangan

- Rancangan Backend: [Draft: Agent Workflow Delivery Backend](https://claude.ai/code/artifact/f8c3fe18-67ff-47b3-a01c-9384b9cd3054)
- Kerangka yang dipakai ulang: [Rancangan workflow agen Mobile](https://claude.ai/artifact/EA7oF3JpM3ahrmgPakUfzV)

Backend memakai kerangka Mobile (empat perintah + `/branch-manager`, tim agen, worktree Orca, flag, alur rilis). Bedanya ada di tiga hal pokok: **tidak ada layar** untuk diuji, ada **migrasi database**, dan Backend adalah **penyedia contract** untuk Mobile dan Frontend web.

## Keputusan implementasi
| Keputusan | Alasan |
| --- | --- |
| Platform dokumentasi `repo` = branch terpisah `agent-docs` di `origin`, worktree `<repo>-docs` | Rancangan meminta Markdown di `docs/` repo. Branch tiket tidak cocok (laporan validasi ada sebelum branch dibuat, laporan audit/rilis tidak punya branch); branch `main` mengubah `<sha-rilis>` dan butuh PR. ADR tetap di branch tiket karena melekat pada kodenya |
| Kunci `deploy:<env>` dipegang dari deploy sampai uji QA selesai | Server dev/beta dipakai bersama: deploy tiket A menimpa kode tiket B, jadi hasil uji tanpa kunci bisa milik tiket lain |
| Slot env per worktree (port + database uji di container) | Pengganti jatah device: agen paralel tidak boleh bentrok port atau data |
| Langkah 6 dipecah: uji lokal di slot (langkah 6), lalu deploy + uji server (langkah 7) | Urutan rancangan menaruh "Schemathesis penuh di dev" sebelum "Deploy dev", padahal kode tiket belum ada di dev saat itu |
| Skill internal hanya untuk 7 skill khas Backend (`/reproduce-request`, `/check-compat`, `/write-migration`, `/test-integration`, `/verify-provider`, `/deploy-service`, `/deploy-variant`) | Skill bersama (`/read-ticket`, `/write-plan`, …) masih langkah di dalam skill flow, sama seperti Mobile hari ini; dipecah bersamaan dengan Mobile supaya tetap satu definisi |
| Contract = OpenAPI 3.1 + versi semver | Format dari workflow produksi tiket (`contract/api.yaml`, `contract.json`); `oasdiff` untuk breaking change |
| Tiket tulisan manual tetap diterima | Workflow produksi tiket saat ini baru membuat tiket role Mobile |
| Guard menambah pagar production DB/env, tulis HTTP ke host production, dan data Docker user | Risiko khas Backend; guard hanya membaca teks perintah, jadi skrip (`test-db.sh`, `migration-check.sh`, `http-evidence.sh`) ikut menolak target non-lokal/production |
| Bukti tekstual (`http-evidence.sh`) pengganti screenshot bertanda | Tidak ada layar; rahasia otomatis disamarkan |
| Stack bebas, tetapi wajib membangkitkan spec OpenAPI 3.x dari kode (anotasi Swagger/generator); diperiksa `openapi-check.sh` | Keputusan user 2026-11-25. Contract tetap sumber kebenaran; spec dari kode = bukti kode memenuhinya. Swagger 2.0 ditolak |
| Platform tiket tidak dipilihkan: default none, agen bertanya di awal; pilihan GitHub Issues + Projects, GitLab issue board, Jira (`ticket-platform.md`) | Keputusan user 2026-11-25. Sejalan dengan `tracker.type` di workflow produksi tiket; guard menjaga Done di ketiganya, dan PR memakai `Refs #n`, bukan `Closes #n` |
| Skrip jalan di Linux dan macOS | Developer Backend sering memakai Linux |

## Masih terbuka
- [x] Stack Backend: bebas, **syarat**: bisa mengekspor spec OpenAPI 3.x dari kode (`rules.md` → Syarat stack). Perintah project tetap dicatat per project di memory.
- [ ] Berapa lama aplikasi mobile versi lama harus tetap didukung (dipakai `/check-compat` dan pola tiga tahap).
- [ ] Siapa yang menjalankan migrasi di production: manusia atau pipeline.
- [ ] Skill khusus stack yang menggantikan `android-cli` dan `kotlin-agent-skills` di Mobile.

---
[← kembali ke README](../README.md)
