# Platform tiket (board)

Workflow ini **tidak terikat ke satu platform tiket**. Semua skill menyebut operasi umum ("baca tiket", "komentar tiket", "geser status"); cara menjalankannya di tiap platform ada di halaman ini.

## Cek awal (wajib, di awal setiap perintah)
1. Baca memory project → **Platform tiket**. Defaultnya **none** (belum pernah ditentukan).
2. **none → berhenti dan tanya user** sebelum langkah apa pun, dengan ringkasan temuan + satu saran:
   | Kondisi repo | Saran |
   |---|---|
   | Tim sudah memakai board tertentu (ada link issue/board di README, tiket, atau kata user) | platform itu |
   | Remote di GitHub, belum ada board | **GitHub Issues + GitHub Projects** (kolom Status) |
   | Remote di GitLab, belum ada board | **GitLab Issues + issue board** (scoped label `workflow::…`) |
   | Tim sudah memakai Jira | **Jira** (butuh konektor Atlassian di Claude) |
   User bingung → jelaskan singkat bedanya, sarankan board bawaan forge repo (GitHub Projects / GitLab board) karena tanpa konektor tambahan. Platform lain → berhenti; belum didukung.
3. Simpan jawaban sebagai memory project tipe `reference`: platform, lokasi (repo `owner/repo` / project GitLab / kunci project Jira), board (nomor GitHub Project + owner / nama board GitLab), **prefix KODE** (lihat bawah), dan cara status dipetakan.
4. Cek akses: GitHub `gh auth status`, GitLab `glab auth status`, Jira `mcp__claude_ai_Atlassian__atlassianUserInfo`. Gagal → berhenti, lapor.
5. Cek status board sudah dipetakan (`~/.agent-workflow/board-transitions.json`, bagian Setup status board). Belum → jalankan setup itu (user yang memilih).

Tiket dari workflow produksi tiket (`sdd-agent-workflow`, `tracker.type` = `github` / `jira`) memakai platform yang sama dengan project itu.

## KODE tiket
KODE dipakai di branch (`fix/<KODE>`), commit, nama worktree (`<repo>-<nomor>`), owner kunci, dan tracing rilis, jadi formatnya selalu `<PREFIX>-<nomor>`:
| Platform | KODE | Rujukan asli |
|---|---|---|
| Jira | kunci Jira apa adanya, mis. `API-123` | `API-123` |
| GitHub | `<PREFIX>-<nomor issue>`, PREFIX dari memory (saran: nama repo singkat huruf besar), mis. `API-123` | `owner/repo#123` |
| GitLab | sama, mis. `API-123` | `group/project#123` |
User boleh mengetik rujukan asli (`#123`, `owner/repo#123`, URL issue); agen mengubahnya ke KODE dan menyebut keduanya di laporan. Commit menulis KODE; di GitHub/GitLab tambahkan `Refs #<nomor>` supaya issue tertaut.

**Jangan pakai kata penutup otomatis** (`Closes #123`, `Fixes #123`, `Resolves #123`) di PR/MR atau commit: forge akan menutup issue saat merge = memindah ke **Done**, padahal Done hanya oleh manusia. Pakai `Refs #123`.

## Operasi per platform
| Operasi | GitHub | GitLab | Jira |
|---|---|---|---|
| Baca tiket + komentar | `gh issue view <n> -R <repo> --comments --json number,title,body,labels,state,comments,url` | `glab issue view <n> -R <project> --comments` | `mcp__claude_ai_Atlassian__getJiraIssue` |
| Cari tiket terkait | `gh issue list -R <repo> --state open --search "<kata> in:title,body" --json number,title,labels,url` | `glab issue list -R <project> --search "<kata>"` | `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` (`text ~ "<kata>"`) |
| Komentar | `gh issue comment <n> -R <repo> --body-file <file>` | `glab issue note <n> -R <project> -m "$(cat <file>)"` | `mcp__claude_ai_Atlassian__addCommentToJiraIssue` |
| Status saat ini | kolom Status item di Project: `gh project item-list <no> --owner <owner> --format json` | scoped label `workflow::…` di issue | field status issue |
| Geser status | `gh project item-edit --id <item-id> --project-id <project-id> --field-id <status-field-id> --single-select-option-id <option-id>`; board berbasis label: `gh issue edit <n> -R <repo> --add-label "<baru>" --remove-label "<lama>"` | `glab issue update <n> -R <project> --label "<baru>" --unlabel "<lama>"` | `mcp__claude_ai_Atlassian__transitionJiraIssue` (id transisi) |
| Tutup / Done | **tidak pernah** (manusia) | **tidak pernah** | **tidak pernah** |

Komentar di semua platform mengikuti gaya `report-format.md` → Komentar tiket (baris pertama link laporan). Link antar tiket tidak dibuat agen; cukup disarankan di komentar.

## Setup status board (sekali per board)
Agen hanya boleh menggeser ke **Todo**, **In Progress**, dan **Ready To Review**. Guard menolak geser status yang tidak terdaftar, juga menutup issue (`gh issue close`, `glab issue close`).
1. Tampilkan pilihan status yang ada ke user:
   - GitHub Projects: `gh project field-list <no> --owner <owner> --format json` → field Status + id opsinya; id project: `gh project view <no> --owner <owner> --format json --jq .id`.
   - Board berbasis label (GitHub/GitLab): daftar label status (mis. `workflow::todo`, `workflow::in progress`, `workflow::ready to review`, `workflow::done`).
   - Jira: `mcp__claude_ai_Atlassian__getTransitionsForJiraIssue` pada satu tiket.
2. User memilih yang dipakai untuk Todo, In Progress, Ready To Review (jangan pernah Done).
3. Tulis lewat Bash (bukan Edit/Write), gabungkan dengan isi lama. Kunci: `jira:<PROJECT>`, `github:<project-id>`, `github-label:<owner/repo>`, `gitlab:<group/project>`. `allow` = id/label yang boleh dituju; `status` (khusus label) = **semua** label status board, termasuk Done, supaya guard tahu label mana yang terlarang.
```bash
S=${AGENT_WORKFLOW_STATE:-$HOME/.agent-workflow}; F="$S/board-transitions.json"
mkdir -p "$S" && { [ -s "$F" ] || echo '{}' > "$F"; } &&
jq '. + {"github:PVT_kwDOAbc":{"allow":["f75ad846","47fc9ee4","98236657"],"names":{"f75ad846":"Todo","47fc9ee4":"In Progress","98236657":"Ready To Review"}}}' "$F" > "$F.tmp" && mv "$F.tmp" "$F"
# contoh lain:
#   "jira:API":{"allow":["11","21","31"],"names":{"11":"Todo","21":"In Progress","31":"Ready To Review"}}
#   "gitlab:grp/api":{"allow":["workflow::todo","workflow::in progress","workflow::ready to review"],
#                     "status":["workflow::todo","workflow::in progress","workflow::ready to review","workflow::done"]}
```
