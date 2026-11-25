# Backend Agent Workflow

Tim agen AI (Claude Code + Orca) yang mengerjakan tiket Jira di proyek **Backend**: mengecek tiket, menulis migrasi database dan kode, menguji API, deploy ke server uji, membuat PR/MR, sampai menyiapkan rilis.

Bayangkan sebuah tim kecil: ada **mandor** (SPV) yang membagi tugas, **programmer** yang menulis kode, **reviewer** yang memeriksa, **QA** yang menguji, dan **petugas rilis** yang deploy dan membuat PR. Kamu cukup mengetik satu perintah; tim agen bekerja, lalu bertanya kepadamu hanya untuk keputusan penting.

> Status: **v1**, kerangka lengkap dan teruji dengan tes otomatis, **belum dicoba di tiket nyata**.
> Workflow saudara: [mobiledev-agent-workflow](https://github.com/roiskhoiron/mobiledev-agent-workflow) (aplikasi mobile) dan [sdd-agent-workflow](https://github.com/roiskhoiron/sdd-agent-workflow) (pembuat tiket).

## Daftar isi
1. [Apa bedanya dengan workflow Mobile?](#apa-bedanya-dengan-workflow-mobile)
2. [Yang perlu disiapkan](#yang-perlu-disiapkan)
3. [Pasang (5 menit)](#pasang-5-menit)
4. [Setup pertama per project](#setup-pertama-per-project)
5. [Lima perintah](#lima-perintah)
6. [Contoh sehari-hari](#contoh-sehari-hari)
7. [Yang tidak pernah dilakukan agen](#yang-tidak-pernah-dilakukan-agen)
8. [Istilah penting](#istilah-penting)
9. [Panduan lanjutan](#panduan-lanjutan)
10. [Isi repo dan merawat dokumen](#isi-repo)

## Apa bedanya dengan workflow Mobile?

| | Mobile | Backend (repo ini) |
|---|---|---|
| Tempat uji | HP, emulator, simulator | Layanan lokal + server dev/beta: request API, log, database uji |
| Bukti di laporan | Screenshot bertanda kotak merah | Request, response, potongan log, hasil query (rahasia otomatis disamarkan) |
| Langkah tambahan | — | **Migrasi database** naik dan turun, diuji bolak-balik |
| Posisi terhadap contract API | Pemakai | **Penyedia**: perubahan tidak boleh merusak aplikasi versi lama |
| Hasil kerja | Build ke Firebase/TestFlight | Deploy ke dev, beta, (production dengan izin) |
| Sumber daya yang dibagi | Device | Port + database uji (satu per tiket), server dev/beta (satu deploy pada satu waktu) |

## Yang perlu disiapkan

| Wajib | Untuk apa |
|---|---|
| [Claude Code](https://code.claude.com) + Orca (sama dengan workflow Mobile) | menjalankan tim agen |
| `git`, `jq`, `python3`, `bash` | skrip dan pagar keamanan |
| Docker | database uji sekali pakai per tiket |
| `gh` (GitHub) atau `glab` (GitLab), sudah login | PR/MR |
| Konektor **Atlassian** (Jira) di Claude | membaca, mengomentari, dan menggeser tiket |

| Disarankan | Untuk apa |
|---|---|
| `schemathesis`, verifier Pact, `oasdiff` | menguji contract API dan mendeteksi perubahan yang merusak klien |
| Konektor **Claude Docs** | bila laporan ingin di Claude Docs, bukan di repo |

Alat yang belum terpasang tidak membuat workflow gagal: test case terkait ditandai **Tertahan** dan agen memberi tahu.

## Pasang (5 menit)

```bash
git clone https://github.com/roiskhoiron/Backend-Agent-Workflow.git
cd Backend-Agent-Workflow
./install.sh          # tautkan skill + agen ke ~/.claude dan pasang pagar keamanan
bash tests/run.sh     # pastikan semua tes lulus (ALL PASS)
```

- `install.sh` aman dijalankan berulang. Pengaturan lama dicadangkan ke `~/.claude/settings.json.bak-backend-workflow`.
- **Sudah memasang workflow Mobile di komputer yang sama?** Nama perintahnya sama (`/develop-tiket`, dst.), jadi `install.sh` berhenti dan memberi tahu. Satu komputer = satu workflow; pakai `./install.sh --force` bila memang ingin beralih ke Backend.

Detail: [docs/pasang.md](docs/pasang.md).

## Setup pertama per project

Cukup sekali. Sebagian besar ditanyakan agen sendiri saat pertama dipakai.

1. **Host production** (wajib, diisi kamu sendiri): tulis host database dan API production, satu per baris, ke `~/.agent-workflow/prod-hosts.txt`. Pagar keamanan memakai daftar ini untuk menolak akses agen ke production.
   ```text
   db.prod.contoh.com
   api.contoh.com
   ```
2. **Akun uji**: salin `templates/qa.env.example` ke root project sebagai `qa.env`, tambahkan `qa.env` ke `.gitignore` **lebih dulu**, lalu isi nilainya.
3. **Status Jira**: saat pertama menggeser tiket, agen menampilkan daftar status dan meminta kamu memilih id untuk Todo, In Progress, dan Ready To Review (Done tidak pernah).
4. **Memory project**: agen bertanya sekali lalu mengingat: branch produksi/integrasi, URL server dev/beta/live, perintah tes/migrasi/deploy, engine database, lokasi spec OpenAPI, klien yang memakai API, dan siapa yang menjalankan migrasi production. Jawabannya juga diberikan sebagai blok `## Catatan agen` untuk kamu commit ke `CLAUDE.md` project.

## Lima perintah

Ketik di Claude Code, di dalam terminal Orca. Alurnya mengikuti papan kanban: **Todo → In Progress → Ready To Review → Done** (Done selalu oleh manusia).

| Perintah | Kapan dipakai | Hasilnya |
|---|---|---|
| `/validate-tiket KODE` | Tiket baru di Todo | Laporan layak/tidak + bukti, komentar Jira, tiket ke In Progress bila layak |
| `/develop-tiket KODE` | Tiket di In Progress | Migrasi + kode + tes, deploy ke dev (dan beta), PR/MR, tiket ke Ready To Review |
| `/rilis-tiket KODE` | QA sudah memberi feedback | Kembalikan ke Todo, deploy ke env lain, atau merge PR tiket (dengan izinmu) |
| `/branch-manager --rilis KODE` | Saatnya rilis versi | Laporan rilis, regresi di beta, PR rilis, tag setelah kamu merge |
| `/audit-issue "keluhan"` | Ada keluhan tapi belum jadi tiket | Laporan penelusuran + saran tiket, **tanpa mengubah apa pun** |

Flag yang sering dipakai:

| Flag | Arti |
|---|---|
| `--solo` | Satu agen mengerjakan semua (hemat, untuk tiket kecil) |
| `--tim` | Dibagi ke beberapa agen (tiket besar, ada migrasi, banyak endpoint) |
| `--batch` (default) | Beberapa tiket digabung: satu deploy dev, satu putaran uji |
| `--separate` | Tiap tiket jalan dan selesai sendiri |

Tanpa flag, agen memilih sendiri. Alur lengkap tiap perintah: [docs/alur-kerja.md](docs/alur-kerja.md).

Perintah di atas memanggil **skill internal** Backend yang tidak perlu kamu ketik: `/reproduce-request`, `/check-compat`, `/write-migration`, `/test-integration`, `/verify-provider`, `/deploy-service`, `/deploy-variant` ([docs/alat.md](docs/alat.md)).

## Contoh sehari-hari

```text
/validate-tiket API-1234                 # cek dulu: layak dikerjakan?
/develop-tiket API-1234                  # kerjakan sampai Ready To Review
/develop-tiket API-1240 API-1241 --tim   # dua tiket sekaligus, dibagi ke tim
/rilis-tiket API-1234                    # setelah QA memberi feedback
/branch-manager --rilis API-1400         # siapkan rilis versi
/audit-issue "checkout kadang error 500 sejak v2.3" --solo
```

Yang terjadi saat `/develop-tiket API-1234`, singkatnya:

```mermaid
flowchart LR
  A[Baca tiket + laporan validasi] --> B[Rencana + slot env sendiri]
  B --> C[Migrasi naik/turun] --> D[Kode + tes] --> E{Review}
  E -- revisi --> D
  E -- bersih --> F[Uji lokal + contract] --> G[Deploy dev, uji di server]
  G --> H[PR siap review + komentar Jira] --> I[Ready To Review]
```

Agen akan **berhenti dan bertanya** bila: deploy production, migrasi yang menghapus/mengubah data, perubahan yang merusak aplikasi versi lama, contract API tidak bisa dipenuhi, atau kredensial tidak ditemukan.

## Yang tidak pernah dilakukan agen

Dijaga oleh pagar keamanan (`hooks/guard.sh`) dan aturan tim:

- Menyentuh **database production** atau menjalankan migrasi dengan env production.
- Menulis data ke server production lewat HTTP (di live hanya membaca).
- Menghapus container/volume Docker milikmu (hanya database uji buatannya sendiri).
- Push ke repo utama (`upstream`), force-push branch utama, atau menimpa tag.
- Memindah tiket ke **Done**, atau merge PR rilis.
- Deploy production tanpa izinmu untuk deploy itu.
- Menulis password/token ke laporan, Jira, atau PR.

Catatan jujur: pagar hanya membaca **teks perintah**. Alamat production yang tersembunyi di `.env` tidak terlihat olehnya, jadi aturan tim tetap berlaku. Detail: [docs/pagar-keamanan.md](docs/pagar-keamanan.md).

## Istilah penting

| Istilah | Penjelasan sederhana |
|---|---|
| **SPV** | Agen "mandor": membaca tiket, membagi tugas, memutuskan tiket selesai |
| **Workspace domain** | Workspace Orca yang kamu buka untuk kerja kode. Root project hanya untuk audit, tanya, dan rilis |
| **Worktree tiket** | Salinan kerja repo khusus satu tiket, folder `<repo>-<nomor>` di sebelah checkout |
| **Slot env** | Jatah port + database uji untuk satu tiket, supaya agen yang bekerja paralel tidak bentrok |
| **Database uji** | Database sekali pakai di Docker, satu per tiket; satu-satunya database yang ditulis tes dan migrasi |
| **Contract** | Spec OpenAPI yang disepakati Backend dan aplikasi pemakainya |
| **Kompatibilitas klien** | Aplikasi mobile versi lama tidak bisa dipaksa update, jadi perubahan yang merusaknya dipecah tiga tahap: tambah baru → klien pindah → hapus lama |
| **Migrasi naik/turun** | Perubahan struktur database dan kebalikannya |
| **Laporan** | Default: file Markdown di branch `agent-docs` repo kamu; bisa juga Claude Docs |
| **`origin` / `upstream`** | `origin` = fork kita (agen boleh push branch); `upstream` = repo utama (hanya lewat PR/MR) |
| **TC / AC** | Test case / acceptance criteria. Hasil TC: Lulus, Gagal, atau Tertahan (dengan alasan) |

## Panduan lanjutan

| Halaman | Isi |
|---|---|
| [Alur kerja](docs/alur-kerja.md) | Tiap perintah langkah demi langkah, semua flag, urutan rilis dengan klien |
| [Tim agen](docs/tim-agen.md) | Peran, nama, dan model tiap agen |
| [Pagar keamanan](docs/pagar-keamanan.md) | Yang diblokir, kapan agen bertanya |
| [Alat](docs/alat.md) | Skrip `bin/`, skill internal, alat uji, konektor (Atlassian, Claude Docs), pembersihan otomatis |
| [Pasang](docs/pasang.md) | Instalasi lengkap dan setup per project |
| [Masalah umum](docs/masalah-umum.md) | Gejala dan cara mengatasinya |
| [Rancangan](docs/design-summary.md) | Keputusan implementasi, alasannya, dan yang masih terbuka |

## Isi repo

| Folder | Isi |
|---|---|
| `skills/<perintah>/SKILL.md` | Langkah tiap perintah (5) dan skill internal Backend (7) |
| `skills/_shared/` | Aturan bersama: `rules.md`, `environments.md`, `credentials.md`, `deploy-release.md`, `report-format.md` |
| `agents/` | Peran agen (model, tugas, larangan) |
| `bin/` | Skrip pembantu: `lock.sh`, `env-slot.sh`, `test-db.sh`, `migration-lint.sh`, `migration-check.sh`, `http-evidence.sh`, `docs-publish.sh`, `release-trace.sh`, `manifest-check.sh`, `audit-mode.sh`, `housekeeping.sh` |
| `hooks/guard.sh` | Pagar keamanan |
| `templates/` | `qa.env.example` (akun uji), bagian `CLAUDE.md` global |
| `tests/` | Tes otomatis: `bash tests/run.sh` |
| `docs/` | Panduan lanjutan |

### Merawat dokumen ini
README untuk pemula: singkat, langsung ke inti. Detail ada di `docs/`. **Setiap perubahan perintah, skrip, atau aturan keamanan wajib memperbarui README atau halaman `docs/` yang sesuai di commit yang sama.** `tests/readme_test.sh` gagal bila ada perintah, skill, skrip `bin/`, atau konektor yang belum disebut.
