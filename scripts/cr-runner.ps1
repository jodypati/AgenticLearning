#Requires -Version 7.0
<#
.SYNOPSIS
  Worker: merges origin/cr ke fu-cr, memproses file Markdown CR via Cursor CLI agent,
  jalankan lint & build, commit, push origin/fu-cr, simpan processed IDs di luar repo.

.DESCRIPTION
  Tanpa menyertakan -DryRun, perilaku default adalah run penuh: merge origin/cr ke checkout fu-cr, Cursor agent (kecuali -SkipAgent),
  npm lint/build, commit jika ada staging, push origin/fu-cr sesuai aturan di skrip. Pakai -DryRun hanya untuk mencetak antrean inbox tanpa efek tersebut.
  State: %LOCALAPPDATA%\apotek-pos-cr-runner\
  Kontrak inbox: pada branch cr, taruh berkas change-request/inbox/*.md dengan frontmatter YAML (id, title wajib id).

.PARAMETER RepoRoot
  Path absolut ke akar repo (default: induk folder scripts/).
.PARAMETER DryRun
  Opsional — hanya log CR di inbox sekarang tanpa merge, agent, atau push (diagnosis/antrean). Tanpa switch ini perilaku default adalah run penuh.
.PARAMETER SkipAgent
  Lewati invokasi agent (uji alur Git + gate npm).
.PARAMETER Sandbox
  Jika aktif: menambahkan --sandbox enabled ke invokasi agent.
.PARAMETER AgentExe
  Path absolut opsional ke executable Cursor CLI (`agent`). Jika kosong, skrip menggunakan perintah `agent` dari PATH.

Detail output tiap jalankan dibuat satu berkas baru di RepoRoot\\change-request\\logs\\
(nama pola cr-runner-yyyyMMdd-HHmmssffffff.log).
#>
[CmdletBinding()]
param(
  [Parameter()][string] $RepoRoot = "",
  [Parameter()][string] $AgentExe = "",
  [switch] $DryRun,
  [switch] $SkipAgent,
  [switch] $Sandbox
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Write-Log([string]$Message) {
  Write-Host ("[{0:u}] {1}" -f (Get-Date).ToUniversalTime(), $Message)
}

function Normalize-RepoRoot([string]$PathIn) {
  if ([string]::IsNullOrWhiteSpace($PathIn)) {
    throw "RepoRoot tidak boleh kosong."
  }
  return (Resolve-Path -LiteralPath $PathIn).Path.TrimEnd('\')
}

function Sync-PathFromRegistry {
  $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
  if ([string]::IsNullOrWhiteSpace($machinePath)) { $machinePath = "" }
  $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
  if ([string]::IsNullOrWhiteSpace($userPath)) { $userPath = "" }
  $sessionPath = "$env:Path"
  $env:Path = ($machinePath.TrimEnd(";") + ";" + $userPath.TrimEnd(";") + ";" + $sessionPath.TrimStart(";")).Trim(";")
}

function Sync-NodeJsBinsToFrontPathIfNeeded {
  if (Get-Command "node" -ErrorAction SilentlyContinue) {
    return
  }

  if (Get-Command "npm" -ErrorAction SilentlyContinue) {
    $npmSrc = (Get-Command "npm").Source
    $dir = Split-Path -Parent $npmSrc
    $nodeExe = Join-Path $dir "node.exe"
    if (Test-Path -LiteralPath $nodeExe -PathType Leaf) {
      $env:Path = $dir.TrimEnd('\') + ";" + $env:Path
      Write-Log "PATH: mendahului folder Node `"$dir`" (node tidak di PATH; diselaraskan dari lokasi npm)."
      return
    }
  }

  $cands = New-Object Collections.Generic.List[string]
  foreach ($frag in @(
      "$env:NVM_SYMLINK",
      "$env:FNM_MULTISHELL_PATH",
      "$(Join-Path $env:ProgramFiles 'nodejs')"
    )) {
    $z = "$frag".Trim()
    if (-not [string]::IsNullOrWhiteSpace($z)) { [void]$cands.Add($z.TrimEnd('\')) }
  }
  $pf86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  if (-not [string]::IsNullOrWhiteSpace($pf86)) {
    [void]$cands.Add((Join-Path ($pf86.TrimEnd('\')) 'nodejs'))
  }
  [void]$cands.Add((Join-Path $env:LOCALAPPDATA 'Programs\nodejs'))

  foreach ($candidate in ($cands | Select-Object -Unique)) {
    $binDir = "$candidate".Trim().TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($binDir)) { continue }
    $nodeExe = Join-Path $binDir "node.exe"
    $npmCmd = Join-Path $binDir "npm.cmd"
    if (-not ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $npmCmd))) {
      continue
    }
    $env:Path = $binDir + ";" + $env:Path
    Write-Log "PATH: menambahkan depan `"$binDir`" - npm tidak ada di PATH sebelumnya (perbaikan tugas terjadwal / penyegaran Node)."
    return
  }
}

# Mengisi $env:CURSOR_API_KEY dari RepoRoot\.env jika variabel sessi kosong. ENV pengguna/me mesin tidak ditimpa.
function Set-CursorApiKeyFromDotEnvIfMissing {
  param([Parameter(Mandatory)][string]$RepoRoot)

  if (-not [string]::IsNullOrWhiteSpace(("$env:CURSOR_API_KEY").Trim())) {
    return [string]"environment"
  }

  $envPath = Join-Path $RepoRoot ".env"
  if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
    return [string]"missing"
  }

  [string]$raw = ""
  try {
    $raw = [System.IO.File]::ReadAllText($envPath, [System.Text.UTF8Encoding]::new($false))
  }
  catch {
    Write-Log ("PERINGATAN: gagal membaca .env (CURSOR_API_KEY tidak diisi dari berkas): {0}" -f $_.Exception.Message)
    return [string]"missing"
  }

  if ($raw.Length -gt 0 -and ($raw[0] -eq [char]0xFEFF)) {
    $raw = $raw.Substring(1)
  }

  foreach ($line in ($raw -split "`r?`n", [System.StringSplitOptions]::None)) {
    $trimLine = $line.Trim()
    if ($trimLine.Length -eq 0 -or $trimLine.StartsWith("#")) { continue }
    if (-not ($trimLine -match '^\s*CURSOR_API_KEY\s*=\s*(.*?)\s*$')) { continue }
    $value = "$($Matches[1])".Trim()
    if (($value.StartsWith("`"") -and $value.EndsWith("`"")) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
      if ($value.Length -ge 2) { $value = $value.Substring(1, $value.Length - 2) }
      $value = $value.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($value)) {
      $env:CURSOR_API_KEY = $value
      return [string]"repo_dotenv"
    }
  }

  return [string]"missing"
}

function Resolve-AgentExeIfProvided {
  param([Parameter(Mandatory)][string]$LiteralExePath)

  $trim = $LiteralExePath.Trim()
  try {
    $resolved = Resolve-Path -LiteralPath $trim -ErrorAction Stop
    if (-not (Test-Path -LiteralPath $resolved.Path -PathType Leaf)) {
      throw "AgentExe bukan berkas: $trim"
    }
    return ([string]$resolved.Path).TrimEnd('\')
  }
  catch {
    throw "AgentExe tidak bisa di-resolve menjadi berkas executable: $trim`n$($_)"
  }
}

function Format-PathHintSnippet {
  $p = "$env:Path"
  $maxLen = [Math]::Min(400, [Math]::Max(0, $p.Length))
  if ($p.Length -le $maxLen) { return $p }
  return ($p.Substring(0, $maxLen) + " ... (dipotong)")
}

function Write-LogCommandProbe {
  param(
    [Parameter(Mandatory)][string] $Label,
    [Parameter(Mandatory)][string] $Status,
    [Parameter()][string] $Detail = ""
  )
  if ([string]::IsNullOrWhiteSpace($Detail)) {
    Write-Log "Probing $Label : $Status"
  }
  else {
    Write-Log ('Probing {0} : {1} | {2}' -f $Label, $Status, $Detail)
  }
}

function Assert-Commands {
  param(
    [switch] $DryRunMode,
    [Parameter()][AllowEmptyString()][string] $AgentExePath = ""
  )

  $hints = @(
    "Untuk tugas Terjadwal, PATH proses sering lebih pendek daripada PowerShell interaktif; cr-runner menyegarkan PATH dari registry User+Machine sebelum pengecekan ini.",
    "Saat memakai schtasks, pastikan Working Directory/Start in menunjuk ke root repo agar jalur npm/agent konsisten.",
    "Nama CLI resmi ialah `agent` (bukan `cursor-agent`). Pakai `-AgentExe` dengan path lengkap ke executable Cursor jika Anda tidak bisa menambah folder instalasi ke PATH."
  )

  $missing = New-Object Collections.Generic.List[string]
  [string]$agentExeResolveError = ""
  foreach ($cmd in @("git")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
      [void]$missing.Add("`"$cmd`"")
    }
  }

  if (-not $DryRunMode) {
    if (-not (Get-Command "npm" -ErrorAction SilentlyContinue)) {
      [void]$missing.Add("`"npm`"")
    }
  }

  $needCursorAgent = (-not ($SkipAgent -or $DryRun))
  [string]$agentExeResolvedPath = ""
  if ($needCursorAgent) {
    if (-not ([string]::IsNullOrWhiteSpace($AgentExePath))) {
      try {
        $agentExeResolvedPath = Resolve-AgentExeIfProvided -LiteralExePath $AgentExePath
      }
      catch {
        $agentExeResolveError = $_.Exception.Message
        [void]$missing.Add("Cursor CLI (AgentExe tidak valid)")
      }
    }
    elseif (-not (Get-Command "agent" -ErrorAction SilentlyContinue)) {
      [void]$missing.Add("`"agent`" (Cursor CLI)")
    }
  }

  if ($missing.Count -gt 0) {
    $list = ($missing | Select-Object -Unique) -join ", "
    Write-Log "ERROR: prasyarat perintah tidak terpenuhi."
    Write-Log ("Tidak tersedia (ringkas): {0}" -f $list)

    $gitGc = Get-Command "git" -ErrorAction SilentlyContinue
    if ($gitGc) { Write-LogCommandProbe -Label "git" -Status "TERSEDIA" -Detail ("path=" + [string]$gitGc.Source) }
    else { Write-LogCommandProbe -Label "git" -Status "TIDAK_DITEMUKAN" -Detail "Get-Command gagal (bukan ada di PATH proses ini)" }

    if ($DryRunMode) {
      Write-LogCommandProbe -Label "npm" -Status "DILEWATI" -Detail "mode DryRun tidak memverifikasi npm"
    }
    else {
      $npmGc = Get-Command "npm" -ErrorAction SilentlyContinue
      if ($npmGc) {
        Write-LogCommandProbe -Label "npm" -Status "TERSEDIA" -Detail ("path=" + [string]$npmGc.Source)
      }
      else {
        Write-LogCommandProbe -Label "npm" -Status "TIDAK_DITEMUKAN" -Detail "Get-Command gagal"
      }
    }

    if (-not $needCursorAgent) {
      Write-LogCommandProbe -Label "Cursor_CLI" -Status "DILEWATI" -Detail "DryRun atau SkipAgent"
    }
    elseif (-not ([string]::IsNullOrWhiteSpace($AgentExePath))) {
      if (-not ([string]::IsNullOrWhiteSpace($agentExeResolveError))) {
        Write-LogCommandProbe -Label "Cursor_CLI(AgentExe)" -Status "GAGAL_RESOLVE" -Detail ($agentExeResolveError -replace "`r?`n", " ")
      }
      else {
        Write-LogCommandProbe -Label "Cursor_CLI(AgentExe)" -Status "TERSEDIA" -Detail ("path=" + $agentExeResolvedPath)
      }
    }
    else {
      $agentGc = Get-Command "agent" -ErrorAction SilentlyContinue
      if ($agentGc) {
        Write-LogCommandProbe -Label "agent" -Status "TERSEDIA" -Detail ("path=" + [string]$agentGc.Source)
      }
      else {
        Write-LogCommandProbe -Label "agent" -Status "TIDAK_DITEMUKAN" -Detail "Get-Command gagal - pertimbangkan -AgentExe"
      }
    }

    $detail = (($hints | ForEach-Object { "  • $_" }) -join "`n")
    $snippet = Format-PathHintSnippet
    throw (
      "Prasyarat perintah tidak terpenuhi: $list`n`n" +
      "Snippet PATH efektif (mungkin dipotong): $snippet`n`n" +
      $detail +
      "`n"
    )
  }
}

function Resolve-AgentExeForInvocation {
  param(
    [Parameter()][AllowEmptyString()][string] $LiteralAgentExeOrEmpty
  )

  if (-not [string]::IsNullOrWhiteSpace($LiteralAgentExeOrEmpty)) {
    return (Resolve-AgentExeIfProvided -LiteralExePath ($LiteralAgentExeOrEmpty.Trim()))
  }
  return "agent"
}

function Get-StateDirectory {
  $base = Join-Path $env:LOCALAPPDATA "apotek-pos-cr-runner"
  if (-not (Test-Path -LiteralPath $base)) {
    New-Item -ItemType Directory -Path $base | Out-Null
  }
  return $base
}

function Test-RetryableExclusiveFileLockFailure([System.Management.Automation.ErrorRecord]$Err) {
  if ($null -eq $Err -or $null -eq $Err.Exception) { return $false }
  $probe = $Err.Exception
  while ($null -ne $probe) {
    $msg = $probe.Message
    if ($probe -is [System.IO.IOException]) { return $true }
    if ($msg -and ($msg.Contains("because it is being used by another process") -or
        $msg.Contains("sedang digunakan") -or
        ($msg.Contains("cannot access") -and $msg.Contains("another")))) {
      return $true
    }
    $probe = $probe.InnerException
  }
  return $false
}

function Acquire-ProcessLock {
  param([Parameter(Mandatory)][string]$LockPath)
  $delayMs = 500
  $attempt = 0
  while ($true) {
    try {
      return [System.IO.File]::Open($LockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    }
    catch {
      $er = $_
      if (-not (Test-RetryableExclusiveFileLockFailure -Err $er)) {
        throw $er
      }
      $attempt++
      if (($attempt % 40) -eq 1 -or ($attempt -ge 120 -and ($attempt % 120) -eq 0)) {
        $reason = ""
        try { $reason = (' ' + ($er.Exception.GetBaseException().Message -replace "[\r\n]+", ' ')) } catch { }
        Write-Log ("INFO: runner.lock belum bisa diambil (proses lain memegang); menunggu... percobaan={0}.{1}" -f $attempt, $reason.TrimEnd())
      }
      Start-Sleep -Milliseconds $delayMs
    }
  }
}

function Load-ProcessedState([string]$StateFile) {
  if (-not (Test-Path -LiteralPath $StateFile)) {
    return @{
      processedIds = [string[]]@()
      entries      = @()
    }
  }
  $raw = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8
  $json = $raw | ConvertFrom-Json

  $ids = [System.Collections.ArrayList]::new()
  if ($null -ne $json.processedIds -and ($json.processedIds | Measure-Object).Count -gt 0) {
    foreach ($x in @($json.processedIds)) { [void]$ids.Add("$x".Trim()) }
  }
  elseif ($null -ne $json.entries) {
    foreach ($e in @($json.entries)) {
      if ($e.id) { [void]$ids.Add("$($e.id)".Trim()) }
    }
  }

  $entries = @()
  if ($json.entries) { $entries = @($json.entries) }

  return @{
    processedIds = @($ids | Select-Object -Unique)
    entries      = $entries
  }
}

function Save-ProcessedState {
  param(
    [string]$StateFile,
    [string[]]$Ids,
    $Entries
  )
  $wrapped = @{ processedIds = @($Ids | Sort-Object -Unique); entries = @($Entries) }
  ($wrapped | ConvertTo-Json -Depth 10) | Set-Content -LiteralPath $StateFile -Encoding UTF8
}

function Read-MarkdownCrMeta {
  param([Parameter(Mandatory)][string]$FilePath)

  $lines = Get-Content -LiteralPath $FilePath -ErrorAction Stop
  if ($lines.Count -lt 3 -or $lines[0] -ne "---") {
    throw "Frontmatter tidak valid pada $FilePath (harus dimulai ---)."
  }

  $map = @{}
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $ln = $lines[$i]
    if ($ln -eq "---") { break }
    if ($ln -match '^\s*([A-Za-z0-9_-]+)\s*:\s*(.*?)\s*$') {
      $key = $matches[1].ToLowerInvariant()
      $val = $matches[2].Trim()
      if ($val.Length -ge 2 -and $val.StartsWith("`"") -and $val.EndsWith("`"")) {
        $val = $val.Substring(1, $val.Length - 2)
      }
      $map[$key] = $val
    }
  }

  if (-not ($map.ContainsKey("id"))) { throw "Bidang YAML 'id' wajib di $FilePath" }
  $idVal = [string]$map["id"].Trim()
  if ([string]::IsNullOrWhiteSpace($idVal)) { throw "YAML 'id' tidak boleh kosong di $FilePath" }

  $titleVal = ""
  if ($map.ContainsKey("title")) { $titleVal = [string]$map["title"] }

  [pscustomobject]@{
    id    = $idVal
    title = $titleVal
    path  = $FilePath
  }
}

function Test-GitRefExists {
  param([string]$WorkingRoot, [string]$RefSpec)
  $null = & git "-C" $WorkingRoot show-ref --verify --quiet $RefSpec 2>$null
  return ($LASTEXITCODE -eq 0)
}

function Invoke-Git {
  param([string]$WorkingRoot, [string[]]$GitArgs)

  & git "-C" $WorkingRoot @GitArgs
  if ($LASTEXITCODE -ne 0) {
    $joined = ($GitArgs -join ' ')
    throw "git gagal dengan exit code $LASTEXITCODE : git $joined"
  }
}

function Assert-GitCleanWorkingTree([string]$WorkDir) {

  & git "-C" $WorkDir update-index --refresh 2>$null | Out-Null
  $porcelain = & git "-C" $WorkDir status --porcelain
  $lines = @($porcelain)
  $nonUntracked = @($lines | Where-Object {
      $_ -and ($_ -notmatch '^\?\? ')
    })
  if ($nonUntracked.Count -gt 0) {
    $fmt = ($lines -join "`n")
    throw "Working tree tidak bersih (ada perubahan terlacak/modifikasi). Segarkan atau commit dahulu. Git status:`n$fmt"
  }
}

function Resolve-FuCrBranch([string]$WorkDir) {

  Invoke-Git $WorkDir @("fetch", "origin")

  $null = & git "-C" $WorkDir rev-parse --verify "origin/cr"
  if ($LASTEXITCODE -ne 0) {
    throw "Remote origin/cr tidak ada. Pastikan branch 'cr' sudah di-push ke origin."
  }

  $haveLocalFu = Test-GitRefExists $WorkDir "refs/heads/fu-cr"
  $haveOriginFu = Test-GitRefExists $WorkDir "refs/remotes/origin/fu-cr"

  if (-not $haveLocalFu -and -not $haveOriginFu) {
    Invoke-Git $WorkDir @("checkout", "--quiet", "-B", "fu-cr", "origin/cr")
    Invoke-Git $WorkDir @("push", "-u", "origin", "fu-cr")
  }
  elseif ($haveLocalFu) {
    Invoke-Git $WorkDir @("checkout", "--quiet", "fu-cr")
    Invoke-Git $WorkDir @("pull", "--ff-only", "origin", "fu-cr")
  }
  else {
    Invoke-Git $WorkDir @("checkout", "--quiet", "-b", "fu-cr", "origin/fu-cr")
    Invoke-Git $WorkDir @("pull", "--ff-only", "origin", "fu-cr")
  }

  Invoke-Git $WorkDir @("merge", "--no-edit", "origin/cr")
}

function Get-InboxMarkdown([string]$WorkDir) {

  $inboxDir = Join-Path $WorkDir "change-request\inbox"
  if (-not (Test-Path -LiteralPath $inboxDir)) {
    Write-Log "Folder inbox tidak ada: $inboxDir"
    return @()
  }

  Get-ChildItem -LiteralPath $inboxDir -Filter "*.md" -File |
    Sort-Object Name |
    ForEach-Object FullName
}

function Add-TrackedFrontendStaging([string]$WorkDir) {
  # Hanya jalur frontend / kontrak proyek; jangan menyentuh inbox atau luar scope.
  $candidates = @(
    "src",
    "index.html",
    "vite.config.ts",
    "tailwind.config.ts",
    "tailwind.config.js",
    "postcss.config.js",
    "components.json",
    "package.json",
    "package-lock.json",
    "eslint.config.js",
    "public",
    "tsconfig.json",
    "tsconfig.app.json",
    "tsconfig.node.json"
  )

  foreach ($rel in $candidates) {
    $full = Join-Path $WorkDir $rel
    if (Test-Path -LiteralPath $full) {
      Invoke-Git $WorkDir @("add", "--", $rel)
    }
  }
}

function Invoke-FrontendVerification([string]$WorkDir) {
  $savedPath = "$env:Path"
  try {
    $npmRef = Get-Command npm -ErrorAction Stop
    $nodeJsDir = Split-Path -Parent $npmRef.Source
    if ("$($npmRef.Source)" -match '\.ps1$') {
      $npmCmdSibling = Join-Path $nodeJsDir "npm.cmd"
      if (Test-Path -LiteralPath $npmCmdSibling -PathType Leaf) {
        $nodeJsDir = [System.IO.Path]::GetDirectoryName((Resolve-Path -LiteralPath $npmCmdSibling).Path)
      }
    }
    $localBin = Join-Path $WorkDir "node_modules\.bin"
    $prefix = $nodeJsDir
    if (Test-Path -LiteralPath $localBin) {
      $prefix = $nodeJsDir + ";" + (Resolve-Path -LiteralPath $localBin).Path
    }
    $env:Path = $prefix + ";" + $env:Path

    Push-Location $WorkDir
    try {
      & npm run lint
      if ($LASTEXITCODE -ne 0) { throw "npm run lint mengembalikan exit code $LASTEXITCODE" }

      & npm run build
      if ($LASTEXITCODE -ne 0) { throw "npm run build mengembalikan exit code $LASTEXITCODE" }
    }
    finally {
      Pop-Location
    }
  }
  finally {
    $env:Path = $savedPath
  }
}

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = Normalize-RepoRoot (Join-Path $PSScriptRoot "..")
}
else {
  $RepoRoot = Normalize-RepoRoot $RepoRoot
}

$runnerLogsDir = Join-Path $RepoRoot "change-request\logs"
New-Item -ItemType Directory -Force -Path $runnerLogsDir | Out-Null
$stamp = Get-Date -Format "yyyyMMdd-HHmmssffffff"
$detailLogPath = Join-Path $runnerLogsDir "cr-runner-$stamp.log"

try { Stop-Transcript | Out-Null }
catch {}

try {

  Start-Transcript -Path $detailLogPath -Force | Out-Null

  Write-Log "===== cr-runner ====="
  Write-Log ("Berkas log detail: change-request/logs/{0}" -f (Split-Path -Leaf $detailLogPath))
  Write-Log "Host=$($env:COMPUTERNAME) User=$($env:USERNAME) PID=$PID"
  Write-Log ("Parameter: RepoRoot=`"{0}`" AgentExe={1} DryRun={2} SkipAgent={3} Sandbox={4}" -f `
      $RepoRoot, `
      ($(if ([string]::IsNullOrWhiteSpace($AgentExe)) { "<default: agent dari PATH>" } else { '"' + ($AgentExe.Trim()) + '"' })), `
      $DryRun.ToString(), `
      $SkipAgent.ToString(), `
      $Sandbox.ToString())

  Sync-PathFromRegistry

  Sync-NodeJsBinsToFrontPathIfNeeded

  Assert-Commands -DryRunMode:$DryRun -AgentExePath "$AgentExe"

  $cursorKeySource = Set-CursorApiKeyFromDotEnvIfMissing -RepoRoot $RepoRoot

  $envKey = "$env:CURSOR_API_KEY".Trim()
  if (-not ($SkipAgent -or $DryRun) -and [string]::IsNullOrWhiteSpace($envKey)) {
    Write-Log "ERROR: CURSOR_API_KEY kosong (wajib untuk agent headless)."
    throw "Variabel lingkungan CURSOR_API_KEY kosong; wajib untuk agent headless."
  }

  # Jangan cetak valor API panjang; tetap dokumentasikan ketersedianya.
  if ($SkipAgent -or $DryRun) {
    Write-Log ("CURSOR_API_KEY: dilewati cek pengaturan lintas mode (DryRun/SkipAgent).")
  }
  else {
    Write-Log ("CURSOR_API_KEY: ada (panjang karakter={0}, sumber={1})." -f $envKey.Length, $cursorKeySource)
  }

  $stateDir = Get-StateDirectory
  $stateFile = Join-Path $stateDir "processed-ids.json"
  $lockFile = Join-Path $stateDir "runner.lock"
  Write-Log "State machine: processed-ids=`"$stateFile`" lock=`"$lockFile`""

  $loaded = Load-ProcessedState $stateFile
  $idList = New-Object Collections.Generic.List[string]
  foreach ($id in @($loaded.processedIds)) { [void]$idList.Add("$id".Trim()) }
  $entriesNew = @(if ($loaded.entries) { $loaded.entries } else { @() })

  $processedSet = New-Object Collections.Generic.HashSet[string]
  foreach ($item in @($loaded.processedIds)) { [void]$processedSet.Add("$item".Trim()) }

  Write-Log ("INFO: Processed ID di state lokal: {0}" -f $processedSet.Count)

  Write-Log ("INFO: Meminta lock eksklusif runner: `"$lockFile`"")
  $lockStream = Acquire-ProcessLock $lockFile
  Write-Log ("INFO: Lock runner diperoleh (PID=$PID).")

  try {

    if ($DryRun) {
      Write-Log "DRY RUN: tidak ada merge/agent/push (mode ini juga tidak memverifikasi npm atau agent di PATH seperti jalur tugas terjadwal penuh). Repo=$RepoRoot"
      foreach ($p in @(Get-InboxMarkdown $RepoRoot)) {
        $metaTry = Read-MarkdownCrMeta $p
        if ($processedSet.Contains($metaTry.id)) {
          Write-Log "(skip tracked) $($metaTry.id) - $p"
        }
        else {
          Write-Log ('ANTREAN: {0} | {1}' -f $metaTry.id, $metaTry.title)
        }
      }
      Write-Log "Selesai dry run (normal)."
      return
    }

    Assert-GitCleanWorkingTree $RepoRoot

    Resolve-FuCrBranch $RepoRoot

    $fuHeadShort = (& git "-C" $RepoRoot rev-parse --short HEAD).Trim()
    $originCrShort = (& git "-C" $RepoRoot rev-parse --short "origin/cr").Trim()
    Write-Log ("Git: sinkron selesai; HEAD checkout=`"$fuHeadShort`" origin/cr=`"$originCrShort`".")

    $inboxDirFull = Join-Path $RepoRoot "change-request\inbox"
    $paths = @(Get-InboxMarkdown $RepoRoot)
    $inboxDirExists = Test-Path -LiteralPath $inboxDirFull
    Write-Log ("Pemindaian inbox: path=`"$inboxDirFull`" ada_folder=$inboxDirExists jumlah_berkas_md={0}" -f $paths.Count)

    $skippedAlready = 0
    $handledNew = 0
    foreach ($crPath in $paths) {
      $meta = Read-MarkdownCrMeta $crPath
      $crId = $meta.id.Trim()

      if ($processedSet.Contains($crId)) {
        Write-Log "Skipping sudah diproses: $crId"
        $skippedAlready++
        continue
      }

      Write-Log "Memproses CR: $crId - $($meta.title)"

      # SHA origin/cr saat pemrosesan (audit)
      $crTip = (& git "-C" $RepoRoot rev-parse --short "origin/cr").Trim()

      $relCr = $crPath.Substring($RepoRoot.Length).TrimStart("\").Replace('\', '/')
      $body = @(
        "Ini adalah tugas change request frontend-only untuk repository Apotek POS (Vite + React)."
        ""
        "Baca permintaan lengkap di file Markdown berikut:"
        "$relCr"
        ""
        "Aturan wajib:"
        "- Lingkup: frontend saja (Vite, React, Tailwind CSS jika digunakan, TanStack Query jika digunakan)."
        "- Dilarang menambahkan backend, server/API routes, atau menambahkan layer server baru."
        "- Boleh memakai data dummy / mock / static JSON di kode frontend."
        "- Ikuti gaya kode dan struktur yang sudah ada di repo; jangan refactor tidak perlu di luar permintaan."
        "- Setelah perubahan, pastikan proyek tetap konsisten dan tidak memecahkan build."
      ) -join "`n"

      if (-not $SkipAgent) {
        Write-Log "Menjalankan agent untuk CR=${crId} ..."
        $agentArgs = @("-p", "--force", "--trust", "--workspace", $RepoRoot)
        if ($Sandbox) {
          Write-Log "Agent sandbox ENABLED."
          $agentArgs += @("--sandbox", "enabled")
        }
        $agentArgs += $body

        $agentProgram = Resolve-AgentExeForInvocation -LiteralAgentExeOrEmpty "$AgentExe"
        Write-Log "Cursor CLI executable: $agentProgram"
        & $agentProgram @agentArgs
        if ($LASTEXITCODE -ne 0) {
          throw "Cursor agent CLI gagal (exit $LASTEXITCODE) untuk CR $crId"
        }
        Write-Log "Agent selesai tanpa gagal sistem untuk CR=${crId}."
      }

      Write-Log "Menjalankan npm lint + build ..."
      Invoke-FrontendVerification $RepoRoot
      Write-Log "npm lint + build OK."

      Add-TrackedFrontendStaging $RepoRoot

      & git "-C" $RepoRoot diff --cached --quiet
      $hasStaging = $LASTEXITCODE -ne 0

      $commitMsgTitle = [regex]::Replace([string]$meta.title, '[\[\]''"]', '').Trim()
      if ([string]::IsNullOrWhiteSpace($commitMsgTitle)) { $commitMsgTitle = $crId }
      $fullMsg = "feat(cr): $crId $commitMsgTitle"

      if (-not $hasStaging) {
        Write-Log "Tidak ada perubahan tersetang untuk staging setelah CR $crId; commit dilewati tetapi verifikasi berhasil."

        [void]$processedSet.Add($crId)
        [void]$idList.Add($crId)
        $entriesNew += [pscustomobject]@{
          id             = $crId
          processedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
          originCrTip    = $crTip
          sourcePath     = $relCr
          note           = "no staged changes"
        }
        Save-ProcessedState -StateFile $stateFile -Ids @($idList.ToArray()) -Entries $entriesNew
        $handledNew++
        continue
      }

      Invoke-Git $RepoRoot @("commit", "-m", $fullMsg)
      Invoke-Git $RepoRoot @("push", "origin", "fu-cr")

      [void]$processedSet.Add($crId)
      [void]$idList.Add($crId)
      $entriesNew += [pscustomobject]@{
        id             = $crId
        processedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        originCrTip    = $crTip
        sourcePath     = $relCr
      }

      Save-ProcessedState -StateFile $stateFile -Ids @($idList.ToArray()) -Entries $entriesNew
      $handledNew++
    }

    if ($paths.Count -eq 0) {
      if (-not $inboxDirExists) {
        Write-Log ("Inbox tidak ditemukan: buat folder `"$inboxDirFull`" dan taruh berkas Markdown (frontmatter id/title) di branch cr, lalu push ke origin/cr. Tidak ada CR untuk diproses pada giliran ini.")
      }
      else {
        Write-Log ("Inbox kosong: tidak ada berkas `*.md` di `"$inboxDirFull`". Tambahkan change request di branch cr pada change-request/inbox/, sinkronkan ke origin/cr, lalu jalankan runner lagi.")
      }
    }
    elseif ($handledNew -eq 0) {
      Write-Log ("Ringkasan giliran: tidak ada CR baru; seluruh {0} berkas .md di inbox sudah tercatat di state lokal. Agent, npm lint/build, dan commit/push untuk CR baru tidak dijalankan pada giliran ini." -f $paths.Count)
    }
    elseif ($skippedAlready -eq 0) {
      Write-Log ("Ringkasan giliran: {0} CR baru selesai diproses pada giliran ini." -f $handledNew)
    }
    else {
      Write-Log ("Ringkasan giliran: {0} berkas di inbox; {1} dilewati (sudah diproses), {2} CR baru selesai diproses." -f $paths.Count, $skippedAlready, $handledNew)
    }
  }
  finally {
    if ($null -ne $lockStream) { $lockStream.Dispose() }
  }

  Write-Log ("Selesai eksekusi cr-runner (keluar normal).")
}
finally {
  try {
    Stop-Transcript | Out-Null
  }
  catch {
  }

  Write-Host ('[DONE] Detail log ditulis pada: "{0}"' -f $detailLogPath)
}
