# Claude Code Plugins — Panduan untuk Tim

> Dokumen ini menjelaskan fitur-fitur ekstensi Claude Code: Sub-Agents, Agent Teams, Skills (+ CMDs), Hooks, dan MCP.

---

## Apa itu Claude Code Plugins?

Claude Code Plugins adalah **bundle** dari berbagai komponen ekstensi:

- Sub-Agents & Agent Teams
- MCP (Model Context Protocol)
- Skills (termasuk CMDs/Slash Commands)
- Hooks
- LSP

Dengan plugins, kamu bisa packaging dan sharing semua konfigurasi ini ke seluruh tim atau project sekaligus.

Referensi: https://medium.com/@alexanderekb/claude-code-plugins-are-confusing-heres-a-quick-start-overview-of-what-s-actually-inside-bb0c2ad1e199

---

## Sub-Agent

Sub-agent adalah kemampuan Claude Code untuk men-**spawn** satu atau lebih agent yang berjalan di **isolated context** tersendiri. Tiap sub-agent punya system prompt, tool permissions, dan bahkan model yang berbeda dari parent session.

Tidak ada shared state antar sub-agent — tiap agent bekerja mandiri dan hanya melaporkan hasil ke parent.

### Kapan digunakan

- Task paralel yang bisa dikerjakan secara independen
- Menjaga main session tetap bersih dari context yang menumpuk
- Spesialisasi tugas (code reviewer, security auditor, explorer, dll.)

### Cara spawn

**Via natural language:**

```
use parallel sub-agents:
- sub-agent 1: review code quality on this feature
- sub-agent 2: review security issue on this feature
```

**Via @mention:**

```
@security-auditor please audit the authentication module
```

**Via `/agents` command** untuk manajemen interaktif di UI.

### Cara membuat custom sub-agent

Buat file markdown di `.claude/agents/` (project-level) atau `~/.claude/agents/` (global):

```markdown
---
name: security-auditor
description: Reviews code for security vulnerabilities. Use when auditing authentication, input validation, or data handling.
tools: Read, Grep, Glob
model: claude-opus-4-6
---

You are a security expert. When reviewing code, focus on:
1. Authentication and authorization flaws
2. Input validation and injection risks
3. Sensitive data exposure
4. Dependency vulnerabilities

Report findings grouped by severity: Critical / High / Medium / Low.
```

### Penting: Batasan sub-agent

- Sub-agent **tidak bisa spawn sub-agent lain** (no infinite recursion)
- Tiap sub-agent punya **context window terpisah** — tidak ada shared state
- Sub-agent hanya bisa **report ke parent**, tidak bisa komunikasi ke sesama sub-agent
- Untuk koordinasi antar agents, gunakan **Agent Teams** (lihat bagian berikut)

### Referensi

- https://timdietrich.me/blog/claude-code-parallel-subagents/
- https://code.claude.com/docs/en/sub-agents
- https://github.com/VoltAgent/awesome-claude-code-subagents

---

## Agent Teams *(fitur baru, Feb 2026)*

Berbeda dari sub-agents biasa, **Agent Teams** memungkinkan multiple Claude sessions untuk saling berkoordinasi — tidak hanya melaporkan ke parent, tapi bisa komunikasi langsung satu sama lain.

### Perbedaan Sub-Agent vs Agent Teams

| | Sub-Agent | Agent Teams |
|---|---|---|
| Komunikasi | Satu arah ke parent | Bisa saling komunikasi |
| Task assignment | Didelegasikan parent | Self-assign dari shared list |
| Cocok untuk | Paralel task sederhana | Workflow kompleks multi-step |
| Rilis | Jul 2025 | Feb 2026 |

### Contoh use case

Satu agent research, satu agent coding, satu agent reviewing — dan mereka bisa koordinasi sendiri tanpa harus melalui parent session. Cocok untuk end-to-end feature development secara otomatis.

Referensi: https://code.claude.com/docs/en/agent-teams

---

## Skills (+ CMDs / Slash Commands)

> ⚠️ **Update penting**: Slash Commands (yang dulu disebut CMDs) sudah **di-merge ke dalam Skills**. Path `.claude/commands/` masih supported sebagai legacy path, tapi canonical path sekarang adalah `.claude/skills/`. Format file-nya sama, Skills mendapat kemampuan tambahan.

Skills adalah predefined instruction set dalam file markdown, yang bisa dipanggil oleh **user secara manual** atau **oleh Claude sendiri** berdasarkan konteks.

### Dua mode invocation

| Mode | Deskripsi |
|------|-----------|
| **User-invocable** | Kamu ketik `/skill-name` secara manual di terminal |
| **Auto-invocable** | Claude membaca field `description` dan memutuskan sendiri kapan skill ini relevan untuk di-load |

Ini yang membedakan Skills dari CMDs lama — sekarang bisa **pasif** (auto-triggered oleh Claude) sekaligus **aktif** (manual oleh user).

### Struktur direktori

```
~/.claude/skills/
└── code-review/
    ├── SKILL.md          ← required, entry point
    ├── checklist.md      ← supporting file (opsional)
    └── scripts/
        └── lint.sh       ← script yang bisa dieksekusi Claude
```

### Contoh SKILL.md

```markdown
---
name: code-review
description: Reviews code for quality, security, and maintainability. Use when user asks to review, audit, or check their code.
disable-model-invocation: false
allowed-tools: Read, Grep, Glob
---

When reviewing code, always check:

1. **Security**: input validation, auth checks, data exposure
2. **Performance**: N+1 queries, unnecessary loops, memory leaks
3. **Maintainability**: naming, complexity, test coverage
4. **Standards**: project conventions (see checklist.md)

Report findings grouped by severity.
```

### Frontmatter fields yang penting

| Field | Fungsi |
|-------|--------|
| `name` | Nama slash command (`/name`). Lowercase, huruf, angka, dan hyphens (max 64 karakter) |
| `description` | Dipakai Claude untuk auto-invoke. **Front-load keyword penting** di awal |
| `disable-model-invocation: true` | Hanya user yang bisa panggil — Claude tidak akan auto-trigger. **Wajib untuk skill dengan side effects** seperti `/deploy` atau `/commit` |
| `user-invocable: false` | Skill tidak muncul di menu `/`, hanya Claude yang bisa invoke (cocok untuk background knowledge) |
| `allowed-tools` | Tools yang pre-approved ketika skill aktif — tanpa prompt permission tambahan |
| `context: fork` | Skill dijalankan di isolated sub-agent context |
| `effort` | Override effort level saat skill aktif (`low`, `medium`, `high`, `max`) |

### Kontrol invocation

| Frontmatter | User bisa invoke | Claude bisa invoke |
|---|---|---|
| (default) | ✅ | ✅ |
| `disable-model-invocation: true` | ✅ | ❌ |
| `user-invocable: false` | ❌ | ✅ |

### Inject dynamic context (shell execution)

Skills mendukung shell execution **sebelum** prompt dikirim ke Claude menggunakan syntax `` !`command` ``:

```markdown
---
name: pr-summary
description: Summarize a pull request for standup
allowed-tools: Bash(gh *)
---

## PR Context
- Diff: !`gh pr diff`
- Comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`

Summarize the above pull request in 3 bullet points for a standup update.
```

Perintah `` !`command` `` dieksekusi terlebih dahulu, output-nya menggantikan placeholder. Claude hanya menerima hasil akhirnya — bukan perintahnya.

### Pass arguments ke skill

Gunakan `$ARGUMENTS` di konten skill:

```markdown
---
name: fix-issue
description: Fix a GitHub issue by number
disable-model-invocation: true
---

Fix GitHub issue $ARGUMENTS following our coding standards.

1. Read the issue description
2. Implement the fix
3. Write tests
4. Create a commit
```

Ketik `/fix-issue 123` → Claude menerima "Fix GitHub issue 123 following our coding standards..."

Untuk argumen by-index: `$ARGUMENTS[0]`, `$ARGUMENTS[1]`, atau shorthand `$0`, `$1`.

### Lokasi skills

| Lokasi | Path | Scope |
|--------|------|-------|
| Enterprise (managed) | via admin | Semua user di org |
| Personal | `~/.claude/skills/` | Semua project milikmu |
| Project | `.claude/skills/` | Project ini saja |
| Plugin | `<plugin>/skills/` | Ketika plugin aktif |

Jika ada nama skill yang sama di beberapa level, prioritas: **enterprise > personal > project**.

### Referensi

- https://code.claude.com/docs/en/skills
- https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf
- https://claude.com/blog/improving-frontend-design-through-skills

---

## CMDs (Slash Commands) — Status Terkini

Seperti disebutkan di atas, CMDs sudah **merged ke Skills**. Tapi beberapa hal yang masih sama:

- CMDs tetap tidak bisa dipakai jika menggunakan `claude -p` (non-interactive/headless mode)
- Kamu masih bisa ketik `/command-name` seperti biasa
- File di `.claude/commands/` tetap jalan (legacy support)

### Contoh built-in commands yang tetap ada

```
/init       Initialize CLAUDE.md baru untuk project
/agents     Manage agent configurations
/hooks      Browse dan kelola hooks yang aktif
/skills     List available skills
/compact    Manual context compaction
/debug      Enable debug logging
```

Perbedaan utama skill vs command sekarang lebih ke **packaging dan UX**: commands adalah single-file entries dengan autocomplete yang bagus di terminal, skills adalah direktori dengan supporting files dan kemampuan auto-invocation.

---

## Hooks

Hooks adalah user-defined shell commands (atau scripts) yang dieksekusi **secara deterministik** pada lifecycle event tertentu di Claude Code.

> **Analogi krusial**: Kalau CLAUDE.md itu "minta Claude untuk selalu X", hooks itu "paksa sistem untuk selalu X".
>
> Test terbukti: aturan "never run rm -rf" di CLAUDE.md diikuti ~70% waktu. Dengan hook? Diblokir **100%**.

Ini berarti untuk safety rules, enforcement keamanan, atau automasi yang tidak boleh miss — gunakan Hooks, bukan CLAUDE.md.

### Lifecycle events yang didukung

| Event | Kapan terjadi |
|-------|--------------|
| `SessionStart` | Saat session dimulai atau di-resume |
| `UserPromptSubmit` | Sebelum prompt diproses Claude |
| `PreToolUse` | Sebelum tool call — bisa **memblokir** eksekusi |
| `PostToolUse` | Setelah tool call sukses |
| `PostToolUseFailure` | Setelah tool call gagal |
| `PermissionRequest` | Saat dialog permission muncul — bisa auto-approve |
| `PermissionDenied` | Saat tool call di-deny oleh classifier |
| `Stop` | Saat Claude selesai merespons |
| `StopFailure` | Saat turn berakhir karena API error |
| `Notification` | Saat Claude butuh input dari user |
| `SubagentStart` / `SubagentStop` | Saat sub-agent spawn/selesai |
| `TaskCreated` / `TaskCompleted` | Saat task dibuat/selesai |
| `PreCompact` / `PostCompact` | Sebelum/sesudah context compaction |
| `ConfigChange` | Saat file settings berubah (untuk audit trail) |
| `FileChanged` | Saat file yang di-watch berubah di disk |
| `CwdChanged` | Saat working directory berubah |
| `SessionEnd` | Saat session berakhir |

### Contoh use cases

#### 1. Desktop notification saat Claude butuh input

```json
{
  "hooks": {
    "Notification": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "notify-send 'Claude Code' 'Butuh perhatianmu'"
      }]
    }]
  }
}
```

#### 2. Auto-format file setelah Claude edit

```json
{
  "hooks": {
    "PostToolUse": [{
      "matcher": "Edit|Write",
      "hooks": [{
        "type": "command",
        "command": "jq -r '.tool_input.file_path' | xargs npx prettier --write"
      }]
    }]
  }
}
```

#### 3. Blokir perintah berbahaya (PreToolUse)

Buat script `.claude/hooks/guard.sh`:

```bash
#!/bin/bash
INPUT=$(cat)
CMD=$(echo "$INPUT" | jq -r '.tool_input.command')

# Blokir perintah destruktif
if echo "$CMD" | grep -qiE "DROP TABLE|rm -rf|git push --force"; then
  echo "Blocked: command ini tidak diizinkan di project ini" >&2
  exit 2  # exit code 2 = blokir + kirim feedback ke Claude
fi

exit 0  # lanjutkan
```

Daftarkan di `.claude/settings.json`:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "./.claude/hooks/guard.sh"
      }]
    }]
  }
}
```

#### 4. Re-inject context setelah context compaction

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "compact",
      "hooks": [{
        "type": "command",
        "command": "echo 'Reminder: gunakan Bun, bukan npm. Jalankan bun test sebelum commit.'"
      }]
    }]
  }
}
```

#### 5. Audit log setiap perubahan config

```json
{
  "hooks": {
    "ConfigChange": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": "jq -c '{timestamp: now | todate, file: .file_path}' >> ~/claude-audit.log"
      }]
    }]
  }
}
```

### Exit codes

| Exit code | Efek |
|-----------|------|
| `0` | Lanjutkan. Output stdout diinjeksi ke context Claude (untuk `SessionStart` dan `UserPromptSubmit`) |
| `2` | **Blokir eksekusi**. stderr dikirim ke Claude sebagai feedback, Claude bisa adjust |
| Lainnya | Lanjutkan, tapi catat sebagai error di transcript dan debug log |

### Tipe hooks selain `command`

| Type | Deskripsi |
|------|-----------|
| `command` | Jalankan shell script (paling umum) |
| `http` | POST event data ke HTTP endpoint — cocok untuk audit logging terpusat atau team-wide enforcement |
| `prompt` | Evaluasi kondisi menggunakan LLM call (default: Haiku) |
| `agent` | Verifikasi menggunakan sub-agent dengan akses tools (bisa read files, run commands) |

### Lokasi konfigurasi hooks

| File | Scope | Shareable? |
|------|-------|-----------|
| `~/.claude/settings.json` | Global, semua project | Tidak (lokal di mesinmu) |
| `.claude/settings.json` | Per-project | Ya, bisa di-commit ke repo |
| `.claude/settings.local.json` | Per-project | Tidak (gitignored) |
| Managed policy | Organization-wide | Ya, via admin |

### Referensi

- https://code.claude.com/docs/en/hooks-guide
- https://code.claude.com/docs/en/hooks (full reference dengan semua event schemas)

---

## MCP (Model Context Protocol)

MCP menghubungkan Claude Code ke tools dan data sumber eksternal — GitHub, database, browser automation, internal APIs, dll.

```bash
# Install MCP server
claude mcp add playwright npx @playwright/mcp@latest

# Gunakan via slash command
/mcp__playwright__create-test [args]
```

> **Performance note**: Claude Code sekarang tidak load semua MCP tool schemas di startup. Hanya nama tool yang di-load, full schema di-fetch on-demand (deferred tool loading). Ini mengurangi context overhead secara signifikan jika kamu punya 50+ MCP tools.

---

## CLAUDE.md — Fondasi Sebelum Semua Feature

Sebelum menggunakan fitur-fitur di atas, pastikan `CLAUDE.md` sudah solid. File ini dibaca Claude di **setiap session** dan berperan sebagai "konstitusi" project.

```markdown
# Project: payment-gateway

## Build & Test
- Build: `make build`
- Test: `make test`
- Lint: `make lint`

## Conventions
- Language: Go
- DB migrations via golang-migrate
- All API responses use envelope format: `{data, error, meta}`
- No direct panic() — return errors ke caller

## Architecture
- Double-entry accounting: lihat `docs/accounting.md`
- QRIS flow: lihat `docs/qris-flow.md`
```

**Catatan penting**: CLAUDE.md bukan rules yang selalu dipatuhi 100% — Claude memperlakukannya sebagai *context*, bukan *law*. Untuk enforcement yang benar-benar deterministic (tidak boleh miss), gunakan **Hooks**.

---

## Rangkuman: Kapan Pakai Apa?

| Kebutuhan | Tool yang tepat |
|-----------|----------------|
| Context/konvensi project yang selalu aktif | CLAUDE.md |
| Workflow reusable yang kamu trigger manual | Skills (`disable-model-invocation: true`) |
| Knowledge/pattern yang Claude auto-apply | Skills (auto-invocable, tanpa flag) |
| Task paralel / isolated execution | Sub-Agents |
| Koordinasi antar multiple agents | Agent Teams |
| Integrasi tools eksternal (GitHub, DB, dll.) | MCP |
| Enforcement deterministik (format, block, notify) | Hooks |
| Bundle semua di atas untuk sharing ke tim | Plugins |

---

## ⚠️ Hal yang Sering Salah Dipahami

1. **CMDs bukan komponen terpisah lagi** — sudah merge ke Skills. File lama di `.claude/commands/` tetap jalan tapi sebaiknya migrasi ke `.claude/skills/`.

2. **Skills bukan hanya passive** — bisa auto-triggered oleh Claude. Untuk skill dengan side effects (deploy, commit, dll.), **wajib** tambahkan `disable-model-invocation: true`.

3. **CLAUDE.md tidak deterministic** — dipatuhi ~70-80% waktu. Untuk safety rules yang tidak boleh miss, gunakan Hooks.

4. **Sub-agents ≠ Agent Teams** — Sub-agents bekerja isolated dan report ke parent. Agent Teams bisa saling komunikasi. Pilih sesuai kebutuhan koordinasi.

5. **`-p` / headless mode** — Slash commands dan interactive features (CMDs) tidak tersedia di mode ini. Gunakan skills via SDK jika perlu automasi non-interactive.

---

*Dokumen ini dibuat berdasarkan dokumentasi resmi Claude Code per April 2026.*
*Official docs: https://code.claude.com/docs/en/overview*