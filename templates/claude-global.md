# Agent workflow Backend (tiket: GitHub / GitLab / Jira)
- Perintah: `/validate-tiket`, `/develop-tiket`, `/rilis-tiket`, `/branch-manager`, `/audit-issue`. Aturan bersama: `~/.claude/skills/_backend-workflow-shared/rules.md`.
- Workspace Orca: root project hanya untuk audit, tanya, `/rilis-tiket`, dan `/branch-manager`; kerja kode di workspace domain yang dibuka user (id `$ORCA_WORKTREE_ID`). Multi-agent = panel split di workspace itu, bukan tab, workspace, atau project baru. Tiap tiket boleh worktree sendiri `<repo>-<nomor>` sejajar checkout domain, dengan slot env sendiri (port + database uji di container).
- Database production tidak pernah disentuh agen; migrasi production dijalankan manusia atau pipeline. Deploy production hanya dengan izin per deploy.
- Keputusan per project tidak ditulis agen ke CLAUDE.md project: agen memberi blok `## Catatan agen` untuk di-commit user.
