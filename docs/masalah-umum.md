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
| "belum punya daftar transisi" | Project baru: agen menunjukkan daftar status, kamu pilih id Todo, In Progress, Ready To Review |
| Schemathesis / oasdiff / verifier Pact tidak ada | TC terkait **Tertahan** + alasan; pasang alatnya lalu ulangi. Agen tidak memasang alat global tanpa izin |
| `migration-lint.sh` menandai migrasi yang sebenarnya aman | Pencocokan berbasis pola bisa keliru. Agen tetap bertanya; kamu yang memutuskan, keputusan dicatat di PR/MR |
| `install.sh` menolak: sudah terhubung ke repo lain | Workflow Mobile terpasang di mesin ini. Pilih satu, atau `./install.sh --force` |
| Linux vs macOS | Skrip memakai `stat -c` lalu `stat -f` (keduanya didukung). Butuh `bash` 4+ (macOS: `brew install bash`) |
| TC **Tertahan** | Tidak bisa diuji (alat tidak ada, butuh data live, spec tidak ada); alasannya tertulis di laporan |

---
[← kembali ke README](../README.md)
