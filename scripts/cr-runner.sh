#!/usr/bin/env bash
# cr-runner.sh — macOS/Linux worker: merge origin/cr → fu-cr, process CR inbox via Cursor CLI,
# npm lint/build, commit/push. State outside repo: ~/Library/Application Support/apotek-pos-cr-runner (macOS).
# Parity target: scripts/cr-runner.ps1 (Windows).
set -euo pipefail

# Widen PATH for launchd/cron (minimal environment).
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT=""
AGENT_EXE=""
DRY_RUN=0
SKIP_AGENT=0
SANDBOX=0

usage() {
  echo "Usage: $0 [--repo-root <path>] [--dry-run] [--skip-agent] [--sandbox] [--agent-exe <path>]" >&2
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -lt 2 ] && usage
      REPO_ROOT="$2"
      shift 2
      ;;
    --dry-run) DRY_RUN=1; shift ;;
    --skip-agent) SKIP_AGENT=1; shift ;;
    --sandbox) SANDBOX=1; shift ;;
    --agent-exe)
      [ $# -lt 2 ] && usage
      AGENT_EXE="$2"
      shift 2
      ;;
    -h|--help) usage ;;
    *) echo "Unknown option: $1" >&2; usage ;;
  esac
done

if [ -z "$REPO_ROOT" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"
fi

write_log() {
  printf '[%s] %s\n' "$(date -u +"%Y-%m-%d %H:%M:%SZ")" "$1"
}

path_hint_snippet() {
  local p="${PATH:-}"
  local max=400
  if [ "${#p}" -le "$max" ]; then
    printf '%s' "$p"
  else
    printf '%s%s' "$(printf '%s' "$p" | head -c "$max")" " ... (dipotong)"
  fi
}

write_log_probe() {
  local label="$1" status="$2" detail="${3:-}"
  if [ -n "$detail" ]; then
    write_log "Probing $label : $status | $detail"
  else
    write_log "Probing $label : $status"
  fi
}

command_path_or_empty() {
  command -v "$1" 2>/dev/null || true
}

set_cursor_api_key_from_dotenv_if_missing() {
  local root="$1"
  local trimmed="${CURSOR_API_KEY:-}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  if [ -n "$trimmed" ]; then
    echo "environment"
    return 0
  fi
  local envpath="$root/.env"
  if [ ! -f "$envpath" ]; then
    echo "missing"
    return 0
  fi
  local py_out
  if ! py_out="$(python3 - "$envpath" <<'PY'
import sys, pathlib, re
p = pathlib.Path(sys.argv[1])
try:
    raw = p.read_text(encoding="utf-8")
except Exception as e:
    print("__READERR__:" + str(e), file=sys.stderr)
    sys.exit(1)
if raw and raw[0] == "\ufeff":
    raw = raw[1:]
for line in raw.splitlines():
    t = line.strip()
    if not t or t.startswith("#"):
        continue
    m = re.match(r"^\s*CURSOR_API_KEY\s*=\s*(.*?)\s*$", line)
    if not m:
        continue
    val = m.group(1).strip()
    if len(val) >= 2 and val[0] == val[-1] and val[0] in "\"'":
        val = val[1:-1].strip()
    if val:
        print(val)
        sys.exit(0)
print("__NONE__")
PY
)"; then
    write_log "PERINGATAN: gagal membaca .env (CURSOR_API_KEY tidak diisi dari berkas)."
    echo "missing"
    return 0
  fi
  if [ "$py_out" != "__NONE__" ] && [ -n "$py_out" ]; then
    export CURSOR_API_KEY="$py_out"
    echo "repo_dotenv"
    return 0
  fi
  echo "missing"
}

resolve_agent_exe_if_provided() {
  local trim="${1:-}"
  trim="${trim#"${trim%%[![:space:]]*}"}"
  trim="${trim%"${trim##*[![:space:]]}"}"
  if [ -z "$trim" ]; then
    echo "agent"
    return 0
  fi
  if [ ! -f "$trim" ]; then
    echo "AgentExe tidak bisa di-resolve menjadi berkas executable: $trim" >&2
    return 1
  fi
  echo "$(cd "$(dirname "$trim")" && pwd)/$(basename "$trim")"
}

assert_commands() {
  local dry_mode="$1"
  local missing=()
  local agent_exe_path="$2"
  local agent_resolved=""
  local agent_resolve_err=""

  if ! command -v git >/dev/null 2>&1; then
    missing+=("\"git\"")
  fi

  if [ "$dry_mode" != "1" ]; then
    if ! command -v npm >/dev/null 2>&1; then
      missing+=("\"npm\"")
    fi
  fi

  local need_agent=1
  if [ "$SKIP_AGENT" = "1" ] || [ "$dry_mode" = "1" ]; then
    need_agent=0
  fi

  if [ "$need_agent" = "1" ]; then
    if [ -n "$agent_exe_path" ]; then
      if ! agent_resolved="$(resolve_agent_exe_if_provided "$agent_exe_path")"; then
        agent_resolve_err="AgentExe tidak valid"
        missing+=("Cursor CLI (AgentExe tidak valid)")
      fi
    else
      if ! command -v agent >/dev/null 2>&1; then
        missing+=("\"agent\" (Cursor CLI)")
      fi
    fi
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  write_log "ERROR: prasyarat perintah tidak terpenuhi."
  write_log "Tidak tersedia (ringkas): $(printf '%s, ' "${missing[@]}" | sed 's/, $//')"

  if command -v git >/dev/null 2>&1; then
    write_log_probe "git" "TERSEDIA" "path=$(command_path_or_empty git)"
  else
    write_log_probe "git" "TIDAK_DITEMUKAN" "command -v gagal (bukan ada di PATH proses ini)"
  fi

  if [ "$dry_mode" = "1" ]; then
    write_log_probe "npm" "DILEWATI" "mode DryRun tidak memverifikasi npm"
  else
    if command -v npm >/dev/null 2>&1; then
      write_log_probe "npm" "TERSEDIA" "path=$(command_path_or_empty npm)"
    else
      write_log_probe "npm" "TIDAK_DITEMUKAN" "command -v gagal"
    fi
  fi

  if [ "$need_agent" != "1" ]; then
    write_log_probe "Cursor_CLI" "DILEWATI" "DryRun atau SkipAgent"
  elif [ -n "$agent_exe_path" ]; then
    if [ -n "$agent_resolve_err" ]; then
      write_log_probe "Cursor_CLI(AgentExe)" "GAGAL_RESOLVE" "$agent_resolve_err"
    else
      write_log_probe "Cursor_CLI(AgentExe)" "TERSEDIA" "path=$agent_resolved"
    fi
  else
    if command -v agent >/dev/null 2>&1; then
      write_log_probe "agent" "TERSEDIA" "path=$(command_path_or_empty agent)"
    else
      write_log_probe "agent" "TIDAK_DITEMUKAN" "command -v gagal - pertimbangkan --agent-exe"
    fi
  fi

  local hints
  hints="$(cat <<'HINTS'
  • Untuk launchd/cron, PATH proses sering lebih pendek; skrip ini menambahkan /opt/homebrew/bin dan /usr/local/bin di awal.
  • Set WorkingDirectory ke repo di plist launchd, atau gunakan --repo-root absolut.
  • Nama CLI resmi ialah agent (bukan cursor-agent). Pakai --agent-exe dengan path lengkap jika perlu.
HINTS
)"
  local snippet
  snippet="$(path_hint_snippet)"
  echo "Prasyarat perintah tidak terpenuhi: ${missing[*]}

Snippet PATH efektif (mungkin dipotong): $snippet

$hints
" >&2
  exit 1
}

get_state_directory() {
  local base=""
  if [ "$(uname -s)" = "Darwin" ]; then
    base="${HOME}/Library/Application Support/apotek-pos-cr-runner"
  else
    base="${XDG_STATE_HOME:-$HOME/.local/state}/apotek-pos-cr-runner"
  fi
  mkdir -p "$base"
  printf '%s' "$base"
}

acquire_mkdir_lock() {
  local lock_dir="$1"
  local max=120
  local i=0
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 1
    i=$((i + 1))
    if [ "$i" -ge "$max" ]; then
      write_log "ERROR: timeout menunggu lock: $lock_dir"
      echo "Jika tidak ada proses lain, hapus folder lock manual: rmdir \"$lock_dir\"" >&2
      exit 1
    fi
  done
}

release_mkdir_lock() {
  local lock_dir="$1"
  rmdir "$lock_dir" 2>/dev/null || true
}

invoke_git() {
  git -C "$REPO_ROOT" "$@" && return 0
  local ec=$?
  echo "git gagal dengan exit code $ec : git $*" >&2
  exit "$ec"
}

git_ref_exists() {
  git -C "$REPO_ROOT" show-ref --verify --quiet "$1" 2>/dev/null
}

assert_git_clean_working_tree() {
  git -C "$REPO_ROOT" update-index --refresh 2>/dev/null || true
  local porcelain
  porcelain="$(git -C "$REPO_ROOT" status --porcelain)"
  if echo "$porcelain" | grep -v '^?? ' | grep -q .; then
    echo "Working tree tidak bersih (ada perubahan terlacak/modifikasi). Segarkan atau commit dahulu. Git status:
$porcelain" >&2
    exit 1
  fi
}

resolve_fu_cr_branch() {
  invoke_git fetch origin
  if ! git -C "$REPO_ROOT" rev-parse --verify "origin/cr" >/dev/null 2>&1; then
    echo "Remote origin/cr tidak ada. Pastikan branch 'cr' sudah di-push ke origin." >&2
    exit 1
  fi
  local have_local_fu=0 have_origin_fu=0
  git_ref_exists "refs/heads/fu-cr" && have_local_fu=1
  git_ref_exists "refs/remotes/origin/fu-cr" && have_origin_fu=1

  if [ "$have_local_fu" -eq 0 ] && [ "$have_origin_fu" -eq 0 ]; then
    invoke_git checkout --quiet -B fu-cr origin/cr
    invoke_git push -u origin fu-cr
  elif [ "$have_local_fu" -eq 1 ]; then
    invoke_git checkout --quiet fu-cr
    invoke_git pull --ff-only origin fu-cr
  else
    invoke_git checkout --quiet -b fu-cr origin/fu-cr
    invoke_git pull --ff-only origin fu-cr
  fi
  invoke_git merge --no-edit origin/cr
}

read_markdown_cr_meta_lines() {
  local fp="$1"
  python3 - "$fp" <<'PY'
import sys, pathlib, re
path = pathlib.Path(sys.argv[1])
lines = path.read_text(encoding="utf-8").splitlines()
if len(lines) < 3 or lines[0].strip() != "---":
    sys.stderr.write(f"Frontmatter tidak valid pada {path} (harus dimulai ---).\n")
    sys.exit(1)
keys = {}
for i in range(1, len(lines)):
    ln = lines[i]
    if ln.strip() == "---":
        break
    m = re.match(r"^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$", ln)
    if not m:
        continue
    key = m.group(1).lower()
    val = m.group(2).strip()
    if len(val) >= 2 and val[0] == '"' and val[-1] == '"':
        val = val[1:-1]
    keys[key] = val
if "id" not in keys:
    sys.stderr.write(f"Bidang YAML 'id' wajib di {path}\n")
    sys.exit(1)
id_val = keys["id"].strip()
if not id_val:
    sys.stderr.write(f"YAML 'id' tidak boleh kosong di {path}\n")
    sys.exit(1)
title_val = keys.get("title", "") or ""
print(id_val)
print(title_val)
PY
}

state_load_ids_lines() {
  python3 - "$1" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file():
    sys.exit(0)
try:
    data = json.loads(p.read_text(encoding="utf-8"))
except Exception as e:
    sys.stderr.write(f"State JSON tidak valid: {e}\n")
    sys.exit(1)
ids = []
if data.get("processedIds"):
    ids = [str(x).strip() for x in data["processedIds"] if str(x).strip()]
elif data.get("entries"):
    for e in data["entries"]:
        if isinstance(e, dict) and e.get("id"):
            ids.append(str(e["id"]).strip())
seen = set()
for x in ids:
    if x not in seen:
        seen.add(x)
        print(x)
PY
}

state_load_entries_json() {
  python3 - "$1" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
if not p.is_file():
    print("[]")
    sys.exit(0)
data = json.loads(p.read_text(encoding="utf-8"))
print(json.dumps(data.get("entries") or [], ensure_ascii=False))
PY
}

save_processed_state() {
  local state_file="$1"
  local ids_nl="$2"
  local entries_json="$3"
  IDS_NL="$ids_nl" ENTRIES_JSON="$entries_json" STATE_OUT="$state_file" python3 <<'PY'
import json, os, pathlib
raw_ids = os.environ.get("IDS_NL", "").splitlines()
ids = sorted(set(x.strip() for x in raw_ids if x.strip()))
entries = json.loads(os.environ["ENTRIES_JSON"])
path = pathlib.Path(os.environ["STATE_OUT"])
path.write_text(json.dumps({"processedIds": ids, "entries": entries}, ensure_ascii=False, indent=2), encoding="utf-8")
PY
}

sanitize_commit_title() {
  local title="$1"
  TITLE_IN="$title" python3 <<'PY'
import os, re
s = os.environ.get("TITLE_IN", "")
s = re.sub(r"[\[\]'\"]", "", s).strip()
print(s)
PY
}

get_inbox_markdown() {
  local inbox="$REPO_ROOT/change-request/inbox"
  if [ ! -d "$inbox" ]; then
    write_log "Folder inbox tidak ada: $inbox"
    return 0
  fi
  find "$inbox" -maxdepth 1 -name '*.md' -type f | sort
}

add_tracked_frontend_staging() {
  local candidates=(
    src index.html vite.config.ts tailwind.config.ts tailwind.config.js
    postcss.config.js components.json package.json package-lock.json
    eslint.config.js public tsconfig.json tsconfig.app.json tsconfig.node.json
  )
  local rel
  for rel in "${candidates[@]}"; do
    if [ -e "$REPO_ROOT/$rel" ]; then
      invoke_git add -- "$rel"
    fi
  done
}

invoke_frontend_verification() {
  ( cd "$REPO_ROOT" && npm run lint )
  ( cd "$REPO_ROOT" && npm run build )
}

append_entry_json() {
  local entries_json="$1"
  local note_field="$2"
  ENTRIES_JSON="$entries_json" CR_ID="$3" TIP="$4" REL="$5" AT="$6" NOTE_FIELD="$note_field" python3 <<'PY'
import json, os
entries = json.loads(os.environ["ENTRIES_JSON"])
entry = {
    "id": os.environ["CR_ID"],
    "processedAtUtc": os.environ["AT"],
    "originCrTip": os.environ["TIP"],
    "sourcePath": os.environ["REL"],
}
if os.environ.get("NOTE_FIELD"):
    entry["note"] = os.environ["NOTE_FIELD"]
entries.append(entry)
print(json.dumps(entries, ensure_ascii=False))
PY
}

ids_array_to_nl() {
  local out=$'\n'
  local x
  for x in "$@"; do
    out+="$x"$'\n'
  done
  printf '%s' "$out"
}

processed_contains() {
  local id="$1"
  shift
  local x
  for x in "$@"; do
    [ "$x" = "$id" ] && return 0
  done
  return 1
}

main_body() {
  local detail_log_path="$1"
  write_log "===== cr-runner (bash) ====="
  write_log "Berkas log detail: change-request/logs/$(basename "$detail_log_path")"
  write_log "Host=$(hostname 2>/dev/null || echo unknown) User=${USER:-unknown} PID=$$"
  write_log "Parameter: RepoRoot=\"$REPO_ROOT\" AgentExe=${AGENT_EXE:-<default: agent dari PATH>} DryRun=$DRY_RUN SkipAgent=$SKIP_AGENT Sandbox=$SANDBOX"

  assert_commands "$DRY_RUN" "$AGENT_EXE"

  local cursor_key_source
  cursor_key_source="$(set_cursor_api_key_from_dotenv_if_missing "$REPO_ROOT")"

  local env_key="${CURSOR_API_KEY:-}"
  env_key="${env_key#"${env_key%%[![:space:]]*}"}"
  env_key="${env_key%"${env_key##*[![:space:]]}"}"
  if [ "$SKIP_AGENT" != "1" ] && [ "$DRY_RUN" != "1" ]; then
    if [ -z "$env_key" ]; then
      write_log "ERROR: CURSOR_API_KEY kosong (wajib untuk agent headless)."
      echo "Variabel lingkungan CURSOR_API_KEY kosong; wajib untuk agent headless." >&2
      exit 1
    fi
  fi

  if [ "$SKIP_AGENT" = "1" ] || [ "$DRY_RUN" = "1" ]; then
    write_log "CURSOR_API_KEY: dilewati cek pengaturan lintas mode (DryRun/SkipAgent)."
  else
    write_log "CURSOR_API_KEY: ada (panjang karakter=${#env_key}, sumber=$cursor_key_source)."
  fi

  local state_dir state_file lock_dir
  state_dir="$(get_state_directory)"
  state_file="$state_dir/processed-ids.json"
  lock_dir="$state_dir/runner.lock.dir"
  write_log "State machine: processed-ids=\"$state_file\" lock=\"$lock_dir\""

  local entries_json
  entries_json="$(state_load_entries_json "$state_file")"

  local id_list=()
  local _lid
  while IFS= read -r _lid || [ -n "${_lid:-}" ]; do
    [ -z "${_lid:-}" ] && continue
    id_list+=("$_lid")
  done < <(state_load_ids_lines "$state_file")

  write_log "INFO: Processed ID di state lokal: ${#id_list[@]}"

  write_log "INFO: Meminta lock eksklusif runner (folder: \"$lock_dir\")"
  acquire_mkdir_lock "$lock_dir"
  write_log "INFO: Lock runner diperoleh (PID=$$)."
  trap 'release_mkdir_lock "$lock_dir"; trap - EXIT' EXIT

  if [ "$DRY_RUN" = "1" ]; then
    write_log "DRY RUN: tidak ada merge/agent/push (mode ini juga tidak memverifikasi npm atau agent di PATH seperti jalur tugas terjadwal penuh). Repo=$REPO_ROOT"
    local p _meta0 _meta1 _dry_meta_lines
    while IFS= read -r p || [ -n "${p:-}" ]; do
      [ -z "${p:-}" ] && continue
      _dry_meta_lines="$(read_markdown_cr_meta_lines "$p")"
      _meta0="$(printf '%s\n' "$_dry_meta_lines" | sed -n '1p')"
      _meta1="$(printf '%s\n' "$_dry_meta_lines" | sed -n '2p')"
      if processed_contains "$_meta0" "${id_list[@]}"; then
        write_log "(skip tracked) $_meta0 - $p"
      else
        write_log "ANTREAN: $_meta0 | $_meta1"
      fi
    done < <(get_inbox_markdown)
    write_log "Selesai dry run (normal)."
    release_mkdir_lock "$lock_dir"
    trap - EXIT
    return 0
  fi

  assert_git_clean_working_tree
  resolve_fu_cr_branch

  local fu_head_short origin_cr_short
  fu_head_short="$(git -C "$REPO_ROOT" rev-parse --short HEAD | tr -d '\n')"
  origin_cr_short="$(git -C "$REPO_ROOT" rev-parse --short origin/cr | tr -d '\n')"
  write_log "Git: sinkron selesai; HEAD checkout=\"$fu_head_short\" origin/cr=\"$origin_cr_short\"."

  local inbox_dir_full paths path_count inbox_exists skipped_already handled_new
  inbox_dir_full="$REPO_ROOT/change-request/inbox"
  paths="$(get_inbox_markdown)"
  if [ -d "$inbox_dir_full" ]; then inbox_exists=1; else inbox_exists=0; fi
  path_count=0
  if [ -n "$paths" ]; then
    while IFS= read -r _pc || [ -n "${_pc:-}" ]; do
      [ -z "${_pc:-}" ] && continue
      path_count=$((path_count + 1))
    done <<< "$paths"
  fi
  write_log "Pemindaian inbox: path=\"$inbox_dir_full\" ada_folder=$inbox_exists jumlah_berkas_md=$path_count"

  skipped_already=0
  handled_new=0

  local cr_path meta_id meta_title cr_id cr_tip rel_cr commit_title full_msg processed_at has_staging
  local agent_program agent_args _meta_lines
  while IFS= read -r cr_path || [ -n "${cr_path:-}" ]; do
    [ -z "${cr_path:-}" ] && continue

    _meta_lines="$(read_markdown_cr_meta_lines "$cr_path")"
    meta_id="$(printf '%s\n' "$_meta_lines" | sed -n '1p')"
    meta_title="$(printf '%s\n' "$_meta_lines" | sed -n '2p')"
    cr_id="$meta_id"

    if processed_contains "$cr_id" "${id_list[@]}"; then
      write_log "Skipping sudah diproses: $cr_id"
      skipped_already=$((skipped_already + 1))
      continue
    fi

    write_log "Memproses CR: $cr_id - $meta_title"

    cr_tip="$(git -C "$REPO_ROOT" rev-parse --short origin/cr | tr -d '\n')"
    rel_cr="${cr_path#$REPO_ROOT/}"

    local body
    body="$(cat <<EOF
Ini adalah tugas change request frontend-only untuk repository Apotek POS (Vite + React).

Baca permintaan lengkap di file Markdown berikut:
$rel_cr

Aturan wajib:
- Lingkup: frontend saja (Vite, React, Tailwind CSS jika digunakan, TanStack Query jika digunakan).
- Dilarang menambahkan backend, server/API routes, atau menambahkan layer server baru.
- Boleh memakai data dummy / mock / static JSON di kode frontend.
- Ikuti gaya kode dan struktur yang sudah ada di repo; jangan refactor tidak perlu di luar permintaan.
- Setelah perubahan, pastikan proyek tetap konsisten dan tidak memecahkan build.
EOF
)"

    if [ "$SKIP_AGENT" != "1" ]; then
      write_log "Menjalankan agent untuk CR=${cr_id} ..."
      agent_program="$(resolve_agent_exe_if_provided "$AGENT_EXE")"
      agent_args=( -p --force --trust --workspace "$REPO_ROOT" )
      if [ "$SANDBOX" = "1" ]; then
        write_log "Agent sandbox ENABLED."
        agent_args+=( --sandbox enabled )
      fi
      write_log "Cursor CLI executable: $agent_program"
      if ! "$agent_program" "${agent_args[@]}" "$body"; then
        echo "Cursor agent CLI gagal untuk CR $cr_id" >&2
        exit 1
      fi
      write_log "Agent selesai tanpa gagal sistem untuk CR=${cr_id}."
    fi

    write_log "Menjalankan npm lint + build ..."
    invoke_frontend_verification
    write_log "npm lint + build OK."

    add_tracked_frontend_staging

    has_staging=0
    if ! git -C "$REPO_ROOT" diff --cached --quiet; then
      has_staging=1
    fi

    commit_title="$(sanitize_commit_title "$meta_title")"
    if [ -z "$commit_title" ]; then
      commit_title="$cr_id"
    fi
    full_msg="feat(cr): $cr_id $commit_title"

    processed_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

    if [ "$has_staging" -eq 0 ]; then
      write_log "Tidak ada perubahan tersetang untuk staging setelah CR $cr_id; commit dilewati tetapi verifikasi berhasil."
      id_list+=("$cr_id")
      entries_json="$(append_entry_json "$entries_json" "no staged changes" "$cr_id" "$cr_tip" "$rel_cr" "$processed_at")"
      save_processed_state "$state_file" "$(ids_array_to_nl "${id_list[@]}")" "$entries_json"
      handled_new=$((handled_new + 1))
      continue
    fi

    invoke_git commit -m "$full_msg"
    invoke_git push origin fu-cr

    id_list+=("$cr_id")
    entries_json="$(append_entry_json "$entries_json" "" "$cr_id" "$cr_tip" "$rel_cr" "$processed_at")"
    save_processed_state "$state_file" "$(ids_array_to_nl "${id_list[@]}")" "$entries_json"
    handled_new=$((handled_new + 1))
  done <<< "$paths"

  if [ "$path_count" -eq 0 ]; then
    if [ "$inbox_exists" -eq 0 ]; then
      write_log "Inbox tidak ditemukan: buat folder \"$inbox_dir_full\" dan taruh berkas Markdown (frontmatter id/title) di branch cr, lalu push ke origin/cr. Tidak ada CR untuk diproses pada giliran ini."
    else
      write_log "Inbox kosong: tidak ada berkas *.md di \"$inbox_dir_full\". Tambahkan change request di branch cr pada change-request/inbox/, sinkronkan ke origin/cr, lalu jalankan runner lagi."
    fi
  elif [ "$handled_new" -eq 0 ]; then
    write_log "Ringkasan giliran: tidak ada CR baru; seluruh $path_count berkas .md di inbox sudah tercatat di state lokal. Agent, npm lint/build, dan commit/push untuk CR baru tidak dijalankan pada giliran ini."
  elif [ "$skipped_already" -eq 0 ]; then
    write_log "Ringkasan giliran: $handled_new CR baru selesai diproses pada giliran ini."
  else
    write_log "Ringkasan giliran: $path_count berkas di inbox; $skipped_already dilewati (sudah diproses), $handled_new CR baru selesai diproses."
  fi

  write_log "Selesai eksekusi cr-runner (keluar normal)."
  release_mkdir_lock "$lock_dir"
  trap - EXIT
}

runner_logs_dir="$REPO_ROOT/change-request/logs"
mkdir -p "$runner_logs_dir"
stamp="$(date -u +"%Y%m%d-%H%M%S")-$(printf '%05d' $$)"
detail_log_path="$runner_logs_dir/cr-runner-${stamp}.log"

main_body "$detail_log_path" > >(tee "$detail_log_path") 2>&1
ec=$?
printf '\n[DONE] Detail log ditulis pada: "%s"\n' "$detail_log_path"
exit "$ec"
