# Masalah umum

| Gejala | Artinya / yang dilakukan |
| --- | --- |
| "DIBLOKIR oleh guard: ..." | Perintah melanggar pagar. Agen melaporkan pesannya, tidak mencari jalan memutar. Pesan biasanya menyebut cara yang benar |
| "akses database production dilarang" / "migrasi ... env production" | Perintah menyebut host di `prod-hosts.txt` atau penanda env production. Agen hanya memakai database uji dan dev; migrasi production oleh manusia/pipeline |
| `env-slot.sh` exit 1: tidak ada slot bebas | Semua slot dipegang worktree lain (atau port-nya dipakai program lain). Tunggu tiket lain selesai, atau hentikan sesi yang sudah tidak dipakai (slotnya lepas sendiri) |
| "Server dev sedang dipakai PROJ-1 … Tunggu atau dahulukan?" | Kunci `deploy:dev` dipegang tiket lain (deploy + uji). **Tunggu** = antre. **Dahulukan** = hubungi pemiliknya; agen tidak merebut kunci orang lain |
| QA: versi di dev tidak cocok | Deploy tertimpa atau belum selesai; bukan kegagalan tiket. Release deploy ulang |
| `test-db.sh` exit 1: belum siap | Docker belum jalan, image belum ter-download, atau port bentrok. Cek `docker logs agentdb-<slug>`, ulangi `up` |
| `docs-publish.sh put` gagal push | Branch `agent-docs` di `origin` maju dari mesin lain; skrip sudah rebase sekali. Masih gagal → cek akses push ke fork |
| "Teammate mode mati" | Buka ulang Claude dengan `claude --teammate-mode auto` atau `/config` → Teammate mode → `auto` |
| "Jalankan dari workspace domain" | `/develop-tiket` dijalankan dari root project. Buka workspace domain di Orca |
| Skill tidak muncul di Codex/Gemini/Cursor | Cek folder skill agent itu (`docs/pasang.md`): global `~/.agents/skills` (Codex/Gemini) atau `~/.cursor/skills` (Cursor); mulai ulang sesi agent |
| Hook Codex tidak jalan | Codex hanya menjalankan hook yang sudah di-*trust*: buka Codex dan setujui hook guard |
| Agent lain menjalankan `--tim` | Hanya Claude Code yang punya teammate; agent lain otomatis solo |
| Agen bertanya "platform tiket mana?" | Memory project masih none. Pilih GitHub Projects, GitLab board, atau Jira (bingung → board bawaan forge repo); dijawab sekali per project |
| "belum punya daftar transisi/status" | Board baru: agen menunjukkan status board, kamu pilih Todo, In Progress, Ready To Review (`skills/_shared/ticket-platform.md`) |
| Guard menolak `gh issue close` / label Done | Disengaja: menutup tiket = Done, hanya manusia |
| Schemathesis / oasdiff / verifier Pact tidak ada | TC terkait **Tertahan** + alasan; pasang alatnya lalu ulangi. Agen tidak memasang alat global tanpa izin |
| `migration-lint.sh` menandai migrasi yang sebenarnya aman | Pencocokan berbasis pola bisa keliru. Agen tetap bertanya; kamu yang memutuskan, keputusan dicatat di PR/MR |
| `install.sh` menolak: sudah terhubung ke repo lain | Workflow Mobile terpasang di mesin ini. Pilih satu, atau `./install.sh --force` |
| Linux vs macOS | Skrip memakai `stat -c` lalu `stat -f` (keduanya didukung). Butuh `bash` 4+ (macOS: `brew install bash`) |
| `openapi-check.sh` bilang Swagger 2.0 | Generator project masih versi lama. Perbarui ke generator OpenAPI 3 (mis. `springdoc`, `drf-spectacular`, `swag` v2); sementara bisa konversi dengan `swagger2openapi` |
| `openapi-check.sh diff` ada `hilang-di-kode` / `response-field-hilang` | Kode atau anotasinya belum memenuhi contract: perbaiki kode/anotasi, jangan ubah contract. `tidak-di-contract` di luar tiket = drift lama, catat saja |
| `openapi-check.sh` minta PyYAML | Ekspor spec sebagai JSON, atau `pip install pyyaml`, atau pasang `yq` |
| TC **Tertahan** | Tidak bisa diuji (alat tidak ada, butuh data live, spec tidak ada); alasannya tertulis di laporan |

---
[← kembali ke README](../README.md)
