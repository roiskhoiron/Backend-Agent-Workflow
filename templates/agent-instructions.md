<!-- backend-agent-workflow:start (dikelola install.sh, jangan diedit manual) -->
# Agent workflow Backend
- `AGENT_WORKFLOW_DIR=__AGENT_WORKFLOW_DIR__` (folder repo workflow). Aturan bersama: `$AGENT_WORKFLOW_DIR/skills/_shared/rules.md`; platform tiket: `$AGENT_WORKFLOW_DIR/skills/_shared/ticket-platform.md`.
- Perintah (skill): `validate-tiket`, `develop-tiket`, `rilis-tiket`, `branch-manager`, `audit-issue`. Agent ini: __AGENT__ (`rules.md` → Agent yang didukung: cara memanggil skill, mode tim, pagar).
- Platform tiket belum ditentukan di memory project → tanya user dulu sebelum langkah apa pun.
- Database production tidak pernah disentuh agen; migrasi production dijalankan manusia atau pipeline. Deploy production hanya dengan izin per deploy. Tiket tidak pernah ditutup/dipindah ke Done oleh agen.
- Keputusan per project tidak ditulis agen ke file instruksi project: agen memberi blok `## Catatan agen` untuk di-commit user.
<!-- backend-agent-workflow:end -->
