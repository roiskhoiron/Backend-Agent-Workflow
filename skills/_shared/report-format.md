# Format laporan

Laporan dipublikasikan oleh agen management (Validator/SPV/Release) ke **platform dokumentasi** project. QA, Contract Runner, dan tim validasi tidak publikasi: mereka menulis file Markdown di folder kerja (`environments.md` → Folder kerja) lalu menyerahkan path-nya ke SPV.

Gaya: Bahasa Indonesia, singkat padat, ramah pemula. Tabel dan diagram mermaid lebih dulu daripada paragraf. Tanpa kredensial (sebut nama kunci saja, mis. `QA_USER1`).

## Platform dokumentasi
Dicatat sekali di memory project (`rules.md` → Lokasi), ditanya sekali bila belum ada. Saran default: `repo`.

| Platform | Tempat | Cara publikasi | Link di Jira |
|---|---|---|---|
| `repo` (default) | Markdown di branch `agent-docs` milik `origin`, worktree `<repo>-docs` sejajar checkout. Branch terpisah dari kode: tidak masuk PR tiket, tidak menggeser `<sha-rilis>` | `docs-publish.sh init <checkout>` sekali, lalu `docs-publish.sh put <docs-worktree> <path> <file> "<pesan>"` | link web dari keluaran `put` |
| `claude-docs` | Claude Docs | `mcp__claude_ai_Claude_Docs__batch` / `update`, sama seperti Mobile | link dokumen |

Lokasi tiap dokumen (platform `repo`; di `claude-docs` jadi judul dokumen):
| Dokumen | Path |
|---|---|
| Laporan validasi | `docs/tickets/<KODE>/validasi.md` |
| Rencana, test case, rencana migrasi | `docs/tickets/<KODE>/rencana.md` |
| Laporan uji: request, response, log | `docs/tickets/<KODE>/uji.md` |
| Laporan audit | `docs/audit/<slug>.md` |
| Perubahan rilis | `docs/rilis/vX.Y.Z.md` |
| Catatan keputusan teknis (ADR) | `docs/adr/NNNN-<judul>.md` **di branch tiket** (ikut PR, karena melekat pada kodenya) |

Dokumen yang diperbarui (validasi ulang, revisi rencana) ditulis ulang di path yang sama; riwayatnya ada di git. **Tunggu link kembali** sebelum berkomentar di Jira; tanpa link → jangan komentar.

## Bukti tekstual
Pengganti screenshot bertanda di Mobile. Tiap TC memuat blok bukti dari `http-evidence.sh` (request, response, durasi; rahasia sudah disamarkan), potongan log, dan bila perlu hasil query, dengan bagian yang salah ditandai:
````markdown
#### TC2 — GET /v1/orders/123
Response: **200**   ← AC2: harus 403, pesanan milik user lain
```log
2026-11-25T10:02:11Z INFO order.show user=41 order=123 owner=77   <<< di sini: tidak ada cek pemilik
```
````
Satu hal penting per penanda; label = kode AC + penjelasan singkat.

## Laporan validasi (`/validate-tiket`)
1. **Judul**: `Validasi PROJ-1234 — judul singkat`, lalu tanggal dan nama user.
2. **Ringkasan**: tabel AC → status (Lulus / Gagal / Tertahan).
3. **Keputusan**: satu kalimat tebal — **Layak**, **Layak dengan catatan**, atau **Tidak layak** — lalu diagram mermaid dan alasan singkat.
4. **Satu bagian per TC** (`TC1 — judul`): hasil di kalimat pertama + alasan satu baris; langkah bernomor; bukti tekstual berurutan sesuai langkah.
5. **Contract & data**: endpoint yang disentuh (spec OpenAPI + versi contract), apakah tiket butuh migrasi, dampak ke klien (versi klien yang masih memakai endpoint itu).
6. **Temuan**: data uji yang dibuat (awalan kode tiket) dan akun yang dipakai (nama kunci); versi/commit yang diuji per server; ref dokumen yang dibaca (hasil sinkron); checklist tindak lanjut (`- [ ] ...`).

**Mode tim** (`--tim`): setelah Keputusan, tambah bagian sebelum TC, masing-masing menyebut agen sumbernya (`<Nama> (<Label>)`) dan tingkat keyakinan (**pasti** / **kuat** / **dugaan**):
- **Bisnis** (PdM): tujuan, AC ↔ aturan bisnis, celah, pertanyaan untuk user.
- **Teknis** (HoE + Contract Runner, + Spesialis eskalasi bila dipanggil): dampak ke blueprint, modul dan tabel yang disentuh, status contract per server, kebutuhan migrasi, ukuran pekerjaan.
- **Ketergantungan** (PjM): tiket/PR → status → dampak; tiket klien (Mobile/Frontend web) yang menunggu endpoint ini; tiket terkait yang tidak di-link (selaras/bertabrakan + kutipan); risiko bentrok, saran urutan.

## Laporan uji (`/develop-tiket`)
1. **Judul**: `Uji PROJ-1234 — judul singkat`, tanggal, nama user.
2. **Ringkasan**: tabel TC → AC → Lulus/Gagal/Tertahan, plus jenis uji (integrasi / Schemathesis / Pact / request manual).
3. **Keputusan**: kalimat tebal **Siap review** atau **Belum siap** + alasan.
4. **Satu bagian per TC**: hasil di kalimat pertama, langkah bernomor, bukti tekstual.
5. **Migrasi**: file, hasil `migration-lint.sh` (merusak data atau tidak, persetujuan user bila ada), hasil `migration-check.sh` (naik → turun → naik), waktu jalan di database uji.
6. **Kompatibilitas klien**: hasil `/check-compat` (Aman / Aman dengan catatan / Memutus) + tahap bila tiga tahap.
7. **Contract**: Schemathesis di dev (lulus/gagal per endpoint), verifikasi Pact per klien (consumer → versi pact → hasil).
8. **Server**: tabel env → base URL → versi ter-deploy; tabel TC × server (dev/beta/live) Lulus/Gagal/Tertahan; endpoint yang sudah dan belum tersedia per server (Matriks env).
9. **Regresi area terdampak**: modul → suite `area-<modul>` → Lulus/Gagal/Tertahan; tes baru yang ditambahkan ke suite.
10. **Temuan**: branch + commit, data uji, checklist tindak lanjut.

## Laporan audit (`/audit-issue`)
Satu dokumen per audit, dibuat di awal audit dengan kerangka per bagian, lalu diisi menjadi laporan final (dokumen yang sama). Urutan bagian:
1. **Ringkasan untuk awam** (3–5 kalimat): apa yang ditanyakan, jawabannya, dan saran utama.
2. **Permintaan asli** + daftar lampiran (terbaca / gagal + alasan).
3. **Temuan per pertanyaan**: tiap klaim dengan bukti (file:baris di ref, commit, potongan log, bukti HTTP, hasil query).
4. **Perbandingan lampiran vs kode vs perilaku API** (bila ada lampiran): tabel `Lampiran | Kode | API | Beda?`.
5. **Akar masalah** + tingkat keyakinan (**pasti** / **kuat** / **dugaan**), dampak, perkiraan ukuran perbaikan.
6. **Saran langkah berikutnya**.
7. **Saran tiket Jira** (opsional, tidak dibuat): judul, deskripsi, AC, endpoint, perlu migrasi atau tidak.
8. **Cara audit**: versi/ref dan server yang diperiksa, alat yang dipakai, hal yang tidak bisa diperiksa (termasuk: guard tidak menangkap tulis lewat shell).

## Laporan rilis (`/branch-manager`)
Dokumen `Perubahan rilis vX.Y.Z`. Urutan isi:
1. Diagram mermaid alur: branch tiket → `<protected>` → `<primary>` → tag → deploy live.
2. Versi + ref asal (hash `<primary>`, `<protected>`, `<sha-rilis>`).
3. Tabel per perubahan:

| KODE | Ringkasan | Branch | PR/MR | Programmer | Status Jira | Migrasi | Kompatibilitas |
|---|---|---|---|---|---|---|---|

4. Commit tak terlacak dan tiket belum Done: ditandai.
5. **Migrasi dalam rilis**: urutan, merusak data atau tidak, siapa menjalankan di production, sebelum/sesudah deploy kode.
6. **Klien yang menunggu**: tiket Mobile/Frontend web yang butuh rilis ini; perubahan tiga tahap dan tahapnya.
7. Matriks env live untuk endpoint semua tiket.
8. Regresi penuh di beta (`<sha-rilis>`, base URL beta): tabel suite → Lulus/Gagal/Tertahan → tiket terkait; bukti untuk yang gagal.
9. Rekomendasi agen.
10. Deploy live (versi + base URL), hasil smoke live, link PR rilis, tag (diisi setelah ada).

## Komentar Jira
Ditulis seperti rekan satu tim yang sopan, dan bisa dipahami pembaca awam (PM, QA, bisnis), bukan hanya developer.

**Gaya**
- Orang pertama **aku**, hangat dan to the point. Hindari "Agen telah…", "Berikut hasil…", kata kaku, emoji berlebihan (paling banyak satu).
- **Bahasa awam:** jelaskan dampaknya bagi pengguna, bukan detail teknisnya. Hindari istilah teknis (endpoint, 404, migrasi, AC, TC, deploy, merge); kalau terpaksa, beri arti singkat dalam kurung. Detail teknis cukup di laporan dan PR/MR.
- **Sapaan**: sapa orang yang dituju. Pakai sapaan yang sudah dipakai tim untuk orang itu; belum ada contoh → **Kak <nama depan>**. Jangan menebak mas/mba dari nama.
- Baris pertama **selalu** memuat link laporan, dibungkus kalimat sapaan.
- Isi: apa yang aku cek, hasilnya, lalu apa yang perlu dari mereka. Tutup dengan terima kasih atau tawaran bantu.
- Kabar kurang enak disampaikan jujur tapi lembut, dengan alasan dan jalan keluar. Tanpa kredensial.

**Contoh — validasi layak dengan catatan**
```
Halo Kak Rina, aku sudah cek tiket ini ya. Laporan lengkapnya di sini: <link laporan>
Tiket ini bisa mulai dikerjakan. Ada satu hal yang perlu dipastikan: data alamat lama akan ikut dipindah ke format baru, jadi aku butuh persetujuan dulu sebelum bagian itu dijalankan.
Tiketnya aku pindah ke In Progress. Terima kasih 🙏
```

**Contoh — Ready To Review**
```
Halo Kak Sari, perubahan di tiket ini sudah siap dicek. Laporan ujinya ada di sini: <link laporan>
Semua yang diminta di tiket sudah aku coba di server uji, dan aplikasi versi lama tetap bisa memakainya.
Server uji: <base URL dev> (versi <sha>) · Perubahan kode: <link PR>
Kalau ada yang kurang pas, tinggal kabari aku ya. Terima kasih!
```

Kirim lewat `mcp__claude_ai_Atlassian__addCommentToJiraIssue`.
