# Aturan bersama tim agen (Backend)

Berlaku untuk semua agen dan skill (`/validate-tiket`, `/develop-tiket`, `/rilis-tiket`, `/branch-manager`, `/audit-issue`, dan skill internal Backend), juga saat hanya satu agen yang bekerja. Kerangka (kanban, tim, worktree, flag, rilis) sama dengan workflow Mobile; yang berbeda: tidak ada device, ada migrasi database, dan Backend adalah **penyedia contract** yang dipakai Mobile dan Frontend web.

## Lokasi
- Dokumen bersama: `~/.claude/skills/_backend-workflow-shared/<file>.md` (`rules.md`, `ticket-platform.md`, `environments.md`, `credentials.md`, `deploy-release.md`, `report-format.md`).
- Skrip: `$AGENT_WORKFLOW_DIR/bin/<skrip>`. Jika `AGENT_WORKFLOW_DIR` kosong, isi dengan folder repo:
  `export AGENT_WORKFLOW_DIR="$(cd "$(readlink ~/.claude/skills/_backend-workflow-shared)/../.." && pwd -P)"`
  Tiap panggilan Bash = shell baru: ulangi export ini di awal panggilan yang memakai skrip.
- State lokal (bukan di repo): `${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}/`: daftar transisi tiket (`board-transitions.json`), host production (`prod-hosts.txt`, diisi user), kunci (`locks/`), slot env (`slots/`), log.
- **Lokasi khusus project tidak pernah ditulis di konfigurasi global** (agen, skill, rules, guard, CLAUDE.md global). Agen membaca memory project Claude Code (`MEMORY.md` project) dan `## Catatan agen` di `CLAUDE.md` project. Belum ada → tanya user sekali (dengan saran dari hasil periksa sendiri), simpan sebagai memory project tipe `reference`, lalu pakai. Berubah/tidak ditemukan → perbarui memory itu setelah bertanya. Isi memory project Backend:

  | Kunci | Isi | Contoh saran dari |
  |---|---|---|
  | **Platform tiket** | `none` (default, belum ditentukan → tanya user di awal perintah) / `github` / `gitlab` / `jira`, lokasi repo/project, board, prefix KODE (`ticket-platform.md`) | remote repo, link issue di README/tiket |
| Branch project | `<primary>` (produksi/live), `<protected>` (integrasi), remote fork/utama, strategi merge PR tiket (squash / merge commit) | `git remote -v`, `git ls-remote --symref upstream HEAD`, `git branch -r` |
  | Server per env | base URL API dev/beta/live, cara melihat versi yang ter-deploy (mis. `GET /version`, tag image) | konfigurasi deploy, `.env.example` |
  | Perintah project | tes unit, tes integrasi, migrasi naik, migrasi turun (hanya migrasi tiket), dump skema, **ekspor spec OpenAPI dari kode**, jalankan layanan lokal, deploy per env | `package.json`, `Makefile`, `pyproject.toml`, `build.gradle`, CI |
  | Database uji | engine + image (`postgres`/`mysql`/`mariadb`/`mongo`), folder migrasi | `docker-compose*.yml`, konfigurasi ORM |
  | Contract | lokasi spec OpenAPI (repo ini atau repo katalog contract dari workflow produksi tiket), lokasi kontrak Pact (folder atau broker) | `openapi*.yaml`, `contracts/`, `pacts/` |
  | Klien | aplikasi yang memakai API ini (Mobile, Frontend web), versi klien tertua yang masih didukung, cara melihat versi klien yang memanggil (header/log) | tiket, dokumen produk |
  | Migrasi production | siapa yang menjalankan: manusia atau pipeline (nama job) | CI/CD |
  | Platform dokumentasi | `repo` (default, branch `agent-docs`) atau `claude-docs` (`report-format.md` → Platform dokumentasi) | tanya |
  | Suite regresi API | folder suite (mis. `tests/regression/`, koleksi Schemathesis/Pact/HTTP), tag `area-<modul>` dan `smoke-live` | repo |
  | Dokumen sumber | business discovery, blueprint/arsitektur, ADR | repo dokumen |

- **Data di beta/live:** uji API di beta boleh menulis data lewat API memakai akun uji (`credentials.md`), data berawalan kode tiket/versi. **Live** hanya method aman (GET/HEAD/OPTIONS) dan flow `smoke-live`; tidak ada login akun nyata atau penulisan data selain akun uji live yang terdaftar di `credentials.md`.

## Tim dan model
| Agen | Model (Orca `--model`) | Tugas | Tidak boleh |
|---|---|---|---|
| SPV | opus (`claude-opus-5-5`) | bagi tugas, slot env, putuskan selesai | kode produk |
| Planner | fable (`claude-fable-5-2`) | rencana + test case + rencana migrasi + cek kompatibilitas (mode tim), analisis eskalasi; atas panggilan SPV | kode produk, platform tiket, deploy, memerintah agen lain |
| Validator | opus (`claude-opus-5-5`) | /validate-tiket; mode tim = SPV validasi | kode produk |
| PdM | sonnet (`claude-sonnet-5-5`) | /validate-tiket tim: dokumen business discovery | menulis repo/tiket/Docs |
| Contract Runner | sonnet (`claude-sonnet-5-5`) | /validate-tiket tim: Schemathesis + Pact endpoint tiket, diff spec vs kode; /develop-tiket: Matriks env awal | fuzzing/menulis data ke beta/live, menulis repo/tiket/Docs |
| HoE | opus (`claude-opus-5-5`) | /validate-tiket tim: kode vs blueprint, contract, skema data, bug logika/API (reproduksi lewat request + log) | menulis repo/tiket/Docs |
| Spesialis eskalasi | fable (`claude-fable-5-2`), on-demand | /validate-tiket tim: hanya saat pemicu eskalasi | menulis repo/tiket/Docs, memutuskan |
| PjM | sonnet (`claude-sonnet-5-5`) | /validate-tiket tim: tiket terkait/blocking, tiket klien yang menunggu endpoint, PR/MR terbuka, risiko bentrok | menulis tiket/PR/Docs |
| Reviewer | opus (`claude-opus-5-5`) | performa query + validasi input/otorisasi, lalu logika vs aturan bisnis; review ditulis di PR/MR | review kode sendiri |
| Release | haiku (`claude-haiku-5-5`) | Draft PR/MR, deploy dev/beta, PR/MR siap review, komentar & geser tiket, merge PR tiket setelah audit (/rilis-tiket), PR revert, tag | Done, deploy production tanpa izin, menjalankan migrasi production, merge PR rilis ke `<primary>` |
| Coder | sonnet (`claude-sonnet-5-5`) | migrasi + TDD di branch sendiri, push rutin branch tiketnya ke `origin` | platform tiket, push selain branch tiketnya, force-push, deploy |
| QA | sonnet (`claude-sonnet-5-5`) | tes integrasi, Schemathesis penuh di dev, Pact sebagai penyedia, regresi area terdampak (/develop-tiket), regresi penuh beta + smoke live (/branch-manager) | platform tiket, push, deploy, menulis data di live |
| Auditor | opus (`claude-opus-5-5`) | /audit-issue: kode, riwayat git, log, reproduksi lewat request | menulis repo/tiket |
| Analis | opus (`claude-opus-5-5`) | /audit-issue: lampiran | menulis repo/tiket |

Product Designer dari workflow Mobile **tidak dipanggil** (tidak ada mockup); di mode tim Contract Runner dan HoE menjadi pemeriksa utama.

Management (SPV, Planner, Validator, Reviewer, Release) memutuskan dan berbicara ke luar: platform tiket, dokumentasi, git remote, deploy. Development (Coder, QA) hanya kode, database uji, dan server dev; satu-satunya akses remote Coder = push branch tiketnya sendiri ke `origin`. Planner hanya penasihat SPV. Tim validasi (PdM, Contract Runner, HoE, Spesialis eskalasi, PjM) hanya-baca dan melapor ke Validator. Housekeeping = skrip shell, tanpa agen. Model diubah di `~/.claude/agents/<peran>.md`.

## Syarat stack: spec OpenAPI dari kode
Stack Backend bebas (bahasa, framework, database), tetapi **wajib bisa membangkitkan spec OpenAPI 3.0/3.1 standar dari kode** (anotasi Swagger atau generator bawaan framework), dengan satu perintah yang tercatat di memory project → Perintah project.

| Stack (contoh) | Generator |
|---|---|
| Node/Express | `swagger-jsdoc` + `swagger-ui-express` |
| NestJS | `@nestjs/swagger` (`SwaggerModule.createDocument`) |
| Java/Kotlin Spring | `springdoc-openapi` (`/v3/api-docs`, plugin Maven/Gradle) |
| Python FastAPI | bawaan (`app.openapi()` / `/openapi.json`) |
| Python Django REST | `drf-spectacular` (`manage.py spectacular`) |
| Go | `swaggo/swag` v2 atau `ogen`/`oapi-codegen` (contract-first) |
| PHP Laravel | `dedoc/scramble` atau `l5-swagger` |
| .NET | `Swashbuckle`/`Microsoft.AspNetCore.OpenApi` |

- Hasilnya diperiksa `openapi-check.sh validate <spec>`: harus OpenAPI 3.x valid. **Swagger 2.0 tidak diterima**: perbarui generator ke OpenAPI 3, atau konversi (`swagger2openapi`) sebagai jalan sementara.
- **Contract tetap sumber kebenaran.** Contract (dari workflow produksi tiket) ditulis lebih dulu; spec dari kode adalah bukti bahwa kode memenuhinya: `openapi-check.sh diff <contract> <spec kode> --paths <endpoint tiket>` harus bersih sebelum review dan sebelum PR siap. Beda → kode diperbaiki, bukan contract.
- Project belum bisa membangkitkan spec → `/validate-tiket` dan `/develop-tiket` berhenti dan tanya, dengan saran generator untuk stack project itu. Menambahkan generator = tiket chore tersendiri.

## Mode kerja
- **Diawasi**: sesi biasa, user menyetujui izin.
- **Otonom**: bypass permission. Pagar di bawah tetap aktif di kedua mode.

## Selalu diblokir (hook `guard.sh`)
- `git push` ke remote selain `origin` (downstream/fork), termasuk `--tags` dan hapus branch. Pengecualian: tag versi `vX.Y.Z` yang ditulis eksplisit (tanpa force/hapus) boleh ke `origin` dan `upstream`.
- Force-push atau hapus `master`/`main`/`develop`.
- **Akses ke database production:** klien database (`psql`, `mysql`, `mongosh`, `pg_dump`, `redis-cli`, …) atau alat migrasi yang menyebut host di `~/.agent-workflow/prod-hosts.txt`; alat migrasi/klien database dengan penanda env production (`NODE_ENV=production`, `RAILS_ENV=production`, `--env=production`, `DJANGO_SETTINGS_MODULE=…prod…`, …).
- **Menulis data ke host production lewat HTTP:** `curl`/`wget`/`http` dengan method tulis atau body ke host di `prod-hosts.txt`.
- **Data Docker milik user:** `docker system|volume|container|network prune`, `docker rm|kill` selain container `agentdb-*`, `docker volume rm` selain volume agen, `docker compose down -v` selain project `agent-*`.
- `rm -r`/`rm -rf` di luar folder project. Pengecualian: artefak build yang bisa dibuat ulang (`build`, `dist`, `target`, `out`, `.gradle`, `node_modules`, `__pycache__`, `.pytest_cache`, `.venv`, `coverage`, …) di worktree lain repo yang sama atau di folder project dari `~/.agent-workflow/build-roots.txt`; isi `${TMPDIR:-/tmp}/{qa,validate,audit}/` bebas dihapus.
- Memindah tiket ke status yang tidak ada di `~/.agent-workflow/board-transitions.json` (Done tidak pernah ada di sana): transisi Jira, opsi Status GitHub Projects, label status GitHub/GitLab.
- Menutup/menghapus tiket (`gh issue close`, `glab issue close`, `gh issue delete`, …): menutup = Done, hanya oleh manusia.
- Edit/Write file di worktree primary; berlaku untuk repo yang punya worktree tambahan (pola Orca).
- Membuka terminal/agen sendiri (`orca terminal split|create`, `orca agent launch`, `worker-start --agent`): agen tambahan selalu **teammate**.
- Membuat project/repo/workspace Orca baru (`orca repo add`, `orca project setup-*`, `--worktree new-child|new-top-level`, `--no-parent`).
- `git worktree add` di luar folder sejajar checkout; `git worktree remove` selain worktree tiket `<repo>-<nomor>` dan worktree rilis `<repo>-rilis-vX.Y.Z`, atau dengan `--force`; `git worktree move`.

Guard hanya membaca **teks perintah**: URL production yang tersembunyi di `.env` atau variabel tidak terlihat olehnya. Karena itu aturan di atas tetap berlaku walau guard diam, dan `test-db.sh`/`migration-check.sh` menolak database yang bukan lokal. Jangan mencari jalan memutar. Jika diblokir, laporkan pesannya ke SPV/user.

## Selalu berhenti dan tanya
0. **Platform tiket belum ditentukan** (memory project = none): tanya dulu, sebelum langkah lain (`ticket-platform.md` → Cek awal).
1. **Deploy production** (tiap kali, izin eksplisit per deploy).
2. **Migrasi yang menghapus atau mengubah data** (`migration-lint.sh` exit 1): tanya dulu, dan rencanakan tiga tahap bila klien masih memakai bentuk lama (`/write-migration`).
3. **Perubahan yang memutus kompatibilitas klien** (`/check-compat` → Memutus): tanya; contract tidak diubah di workflow ini.
4. **Contract tidak bisa dipenuhi** (temuan Planner/HoE): alur berhenti, operator menjalankan `/modify-epic-ticket` di workflow produksi tiket.
5. Sebelum memulai hotfix (sementara manual).
6. Kredensial tidak ditemukan, atau mengarah ke production.
7. Dua fix hotfix bentrok (mode tim: SPV minta analisis opsi dari Planner dulu, lalu tanya).
8. `deploy:<env>` dipegang tiket lain: tunggu atau dahulukan (`environments.md` → Server bersama).

Cara tanya:
- Teammate: tanya ke SPV lewat SendMessage dan tunggu jawabannya; SPV yang bertanya ke user.
- SPV/sesi utama: tanya di chat dan tunggu jawaban.

## Periksa dulu, lalu tanya
Sebelum bertanya, kumpulkan fakta sendiri (git log, branch `<primary>`/`<protected>`, versi yang ter-deploy di tiap server, file project, spec OpenAPI). Ajukan pertanyaan dengan ringkasan temuan dan **satu saran**. Baca dulu `## Catatan agen` di `CLAUDE.md` project. Agen tidak menulis `CLAUDE.md` sendiri (worktree primary diblokir guard): jawaban user + temuan diberikan sebagai blok `## Catatan agen` siap tempel, untuk di-commit user sendiri. Kredensial tidak pernah dicatat.

## Workspace & worktree (Orca)
Workspace = item Orca tempat terminal agen tampil: git worktree, atau workspace folder (`<repo-id>::<path>::workspace:<uuid>`, path sama dengan folder project).

**Kenali domain:** `$ORCA_WORKTREE_ID` = workspace terminal ini; cari di `orca worktree list --json` (`id` sama) → `displayName` = domain, `path`, `isMainWorktree`. Jangan pakai `orca worktree current` untuk ini. Tidak ketemu → tanya user nama domainnya.
- **Root project** (`isMainWorktree: true`): hanya audit, tanya, `/rilis-tiket`, dan `/branch-manager`.
- **Domain** = workspace yang dibuka user. **Semua agen batch bekerja di dalam domain itu saja**: satu sesi atau teammate yang tampil sebagai panel split di workspace yang sama.
  - Domain git worktree: kerja di checkout workspace itu.
  - Domain workspace folder: checkout domain = `<path>/<repo>-<slug>` (slug = `displayName` huruf kecil, spasi → `-`). Belum ada → buat sejajar worktree lain repo itu: `git -C <worktree repo itu> worktree add ../<repo>-<slug> -b batch/<slug> <base>`, sebut di laporan.
  - **`<base>` selalu ref remote terbaru:** `git fetch upstream` (+ `git fetch origin` bila perlu), lalu:
    | Tiket | `<base>` |
    |---|---|
    | Hotfix | `upstream/<primary>` atau tag versi live; sementara ditangani manual dengan bertanya |
    | Feature request / fix / chore / docs lainnya | `upstream/<protected>` |
    Jenis tiket ragu → tanya. Catat base + hash (`git rev-parse --short <base>`) di rencana.
  - Checkout domain tetap di **branch batch** (lokal saja). Tiap tiket punya **worktree tiket** sejajar checkout domain, `<repo>-<nomor>` (nomor = angka KODE): `git -C <checkout domain> worktree add ../<repo>-<nomor> -b <feature|fix|...>/<KODE> <base>`. Tulis path apa adanya, tanpa variabel (guard memeriksa teks perintah). Sudah ada → pakai; tertinggal dari base (`git rev-list --count HEAD..<base>` > 0) → laporkan jumlah commit lalu tanya rebase/merge atau lanjut.
  - Tiket berbeda jalan **paralel** di worktree masing-masing. Beberapa coder di satu tiket hanya bila file/modulnya terpisah, dan **hanya satu coder per tiket yang menulis migrasi**.
- **Slot env per worktree** (pengganti jatah device Mobile): setelah worktree tiket dibuat, SPV mengambil slot `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/env-slot.sh" acquire <worktree> <KODE>-spv1` → port layanan + database uji sendiri (`environments.md`). Semua agen di worktree itu memakai env slot itu.
- **Cadangan (C):** tidak aman dibagi (coder menyentuh file yang sama, dua migrasi di modul yang sama, worktree dipakai batch lain) → satu agen (solo) saja, atau berhenti dan tanya.
- **Kunci checkout:** sebelum mengubah branch/file di checkout domain atau worktree tiket, `AGENT_LOCK_PID=$PPID "$AGENT_WORKFLOW_DIR/bin/lock.sh" acquire checkout:<path> <KODE atau domain>`; dipegang batch lain → cadangan C. Lepas saat selesai/berhenti.
- **Bersihkan setelah Ready To Review** (hanya yang dibuat batch ini):
  1. `test-db.sh down <worktree>` lalu `env-slot.sh release <worktree> <owner>`.
  2. Hapus worktree tiket bila `git -C <worktree> status --porcelain` kosong dan `git -C <worktree> log @{u}..` kosong: `git -C <checkout domain> worktree remove ../<repo>-<nomor>` (tanpa `--force`; branch tetap ada). Syarat tidak terpenuhi → biarkan, hapus artefak build-nya saja (path literal), sebut di laporan.
  Checkout domain dan worktree buatan user tidak pernah dihapus.
- **Dilarang (juga guard):** project/repo/workspace Orca baru, worktree di luar folder project, `git worktree remove --force`, `git worktree move`. `/rilis-tiket` boleh membuat ulang worktree tiket `<repo>-<nomor>` dari `origin/<branch tiket>` untuk deploy variant dan menghapusnya lagi bila bersih. `/branch-manager` memakai worktree sementara detached `<repo>-rilis-vX.Y.Z` dan menghapusnya setelah smoke live.

Orkestrasi (SPV sebagai lead): tiap worker = **teammate** Claude Code (agent teams), tampil sebagai panel split di tab SPV.
- **Syarat:** sesi SPV jalan dengan teammate mode (`claude --teammate-mode auto`, atau `/config` → Teammate mode = auto). Tool Agent tanpa parameter `name` = mode itu mati → tanya user: buka ulang sesi dengan teammate mode (saran), atau lanjut solo.
- **Panggil:** tool Agent dengan `name: "<Nama>-<Label><n>"`, `subagent_type: <peran>` (`planner`, `coder`, `reviewer`, `qa`, `release`, `auditor`, `analis`, `pdm`, `contract-runner`, `hoe`, `eskalasi`, `pjm`) dan `model` sesuai peran (Planner dan Spesialis eskalasi: jangan isi `model`, frontmatter yang berlaku). Prompt: "Ikuti `~/.claude/agents/<peran>.md`" + tugas (kode tiket, worktree, env slot, batas file, akun uji, folder laporan).
- **Lapor & tanya:** lewat SendMessage ke SPV. Daftar tugas bersama tim melacak tugas per tiket.
- **Pantau sampai tuntas (wajib, SPV):** rentang tunggu ±10 menit; tiap rentang cocokkan daftar tugas dengan teammate yang berjalan, tulis satu baris status ke user. Teammate diam lebih dari satu rentang → minta status; tetap diam → cek jejaknya (commit/push, file laporan, kunci `deploy:*`/slot); macet → lepas kuncinya, hentikan, tugaskan ulang ke nama berikutnya dengan konteks posisi terakhir. Selesai hanya bila hasilnya terbukti ada (commit ter-push, komentar review di PR/MR, laporan, link deploy/PR), lalu hentikan teammate itu.
- **Pakai ulang:** tugas lanjutan untuk agen yang sama → SendMessage ke nama yang sama. Tidak pernah ada dua `Maman-Programmer1`. Pekerjaan paralel → nama berikutnya.
- **Hentikan:** peran yang tugasnya habis → shutdown saat itu juga. Akhir batch atau berhenti lebih awal → hentikan semua teammate batch ini.
- Mode izin teammate mengikuti sesi SPV.

**Nama agen** (`name` teammate; di laporan/komentar ditulis `<Nama> (<Label><n>)`): sama dengan workflow Mobile.
| Peran | Label | Nama berurutan |
|---|---|---|
| SPV | SPV | Pak Darmo |
| Planner | Planner | Pak Sastro |
| Validator | Validator | Kang Jajang |
| Coder | Programmer | Maman, Ujang, Tarjo, Asep, Parmin |
| Reviewer | Reviewer | Mbah Karto |
| QA | QA | Paijo, Euis, Ningsih |
| Release | Release | Sutini |
| Auditor | Auditor | Cecep, Dadang, Sarip |
| Analis | Analis | Bu Lastri |
| PdM | PdM | Bu Ratmi |
| Contract Runner | Kontrak | Kang Ohim |
| HoE | HoE | Pak Harjo |
| Spesialis eskalasi | Eskalasi | Eyang Wiryo |
| PjM | PjM | Bu Sumi |
Owner kunci tetap `<KODE>-<peran><n>` (mis. `PROJ-12-qa1`, `PROJ-12-release1`).

## Git
- Branch kerja: `feature/` `fix/` `hotfix/` `docs/` `chore/` + kode tiket (mis. `fix/PROJ-1234`), dibuat di downstream.
- Commit menyebut kode tiket (dibaca `release-trace.sh`); di GitHub/GitLab tambahkan `Refs #<nomor>`. **Jangan** `Closes/Fixes/Resolves #<nomor>` di commit atau PR/MR: forge menutup issue saat merge (= Done). File migrasi ikut commit yang sama dengan kode yang memakainya.
- Tag versi `vX.Y.Z` (beranotasi) dibuat Release setelah PR rilis di-merge manusia, di commit hasil merge, lalu di-push ke `upstream` dan `origin`. Tag tidak pernah di-force atau dihapus. Versi Backend dikenali dari **tag + hash commit**, tidak ada nomor build.
- Push hanya oleh Release (branch ke `origin`; tag versi ke `upstream` dan `origin`), kecuali Coder push branch tiketnya dan sesi utama (Validator/SPV/Release) push branch dokumen `agent-docs` ke `origin` lewat `docs-publish.sh put`. Teammate (termasuk Planner) tidak menjalankan `docs-publish.sh put`: mereka menyerahkan file Markdown ke SPV untuk dipublikasikan.

## Platform tiket dan status board
Workflow tidak terikat ke satu platform tiket. Platform (GitHub Issues + Projects, GitLab issue board, atau Jira), cara membaca/mengomentari/menggeser tiket, format KODE, dan **setup status board** ada di `ticket-platform.md`. Default memory project = **none**: setiap perintah memulai dengan "Cek awal" di sana, dan bila platform belum ditentukan agen **bertanya ke user dulu**.

## Setup host production (sekali per mesin)
`~/.agent-workflow/prod-hosts.txt` = satu host per baris (host database production, host API live, replika). Subdomain ikut cocok. Diisi **user**, bukan agen. Belum ada → agen menyarankan isinya (dari memory project → Server per env) dan meminta user membuatnya; tanpa file ini guard hanya mengenali penanda env production.

## Gaya tulis (laporan, komentar tiket, pertanyaan)
Bahasa Indonesia, singkat padat, ramah pemula; tabel dan diagram mermaid lebih dulu daripada paragraf. Komentar tiket: humanis dan mudah dipahami pembaca awam (tanpa istilah teknis), orang pertama "aku", sapaan ramah, baris pertama memuat link laporan. Detail format: `report-format.md`. Kredensial tidak pernah ditulis ke dokumen/tiket/MR.
