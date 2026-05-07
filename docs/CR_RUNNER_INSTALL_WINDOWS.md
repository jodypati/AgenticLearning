# Instalasi Change Request Runner (Cursor CLI + Windows)

Panduan ini menjelaskan persiapan mesin Windows agar otomasi `scripts/cr-runner.ps1` dapat mengambil change request dari branch `cr`, menjalankan agen Cursor CLI, lalu mengommit serta push ke branch `fu-cr`.

Untuk checklist operasional harian dan verifikasi, lihat juga [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md).

## Prasyarat

- **Windows** 10 atau 11.
- **Git** untuk Windows; credential untuk `fetch`/`push` (misalnya SSH key atau [Git Credential Manager](https://github.com/git-ecosystem/git-credential-manager) dengan PAT yang punya akses repo).
- **Node.js LTS** (disertakan `npm`) agar tahap `npm run lint` dan `npm run build` dalam skrip bisa jalan.
- **Akses** ke remote Git (biasanya `origin`) dan hak **push ke branch `fu-cr`** untuk akun pengguna yang menjalankan worker.
- **Cursor CLI**: pasang ikon panduan umum menggunakan PowerShell seperti di dokumentasi Cursor ([Installation](https://cursor.com/docs/cli/installation)).

Setelah instalasi CLI, tutup terminal lalu buka lagi atau pastikan **`agent`** tersedia di PATH:

```powershell
agent --version
agent status
```

`cr-runner.ps1` menyegarkan `$env:Path` dari nilai PATH **Machine** dan **User** di registry tepat setelah konteks tugas dibuka, supaya tugas Terjadwal / `powershell -NoProfile` masih bisa menemukan `npm` dan `agent` sama seperti konsol Anda. Jika suatu lokasi Anda butuh tidak termasuk kedua penyimpanan ENV itu (jarang terjadi), gunakan **` -AgentExe "C:\...\agent.exe"`** dengan path lengkap ke executable Cursor.

## Otentikasi agen Headless (`CURSOR_API_KEY`)

Anda bisa menyimpan kunci di **variabel lingkungan User/Machine/session** (disarankan untuk override eksplisit) atau sebagai **fallback** di berkas **`.env` di akar repo** dengan satu baris `CURSOR_API_KEY=...` (UTF-8). `cr-runner.ps1` hanya menggunakan `.env` jika `CURSOR_API_KEY` di lingkungan proses masih kosong setelah dipangkas; ENV tidak akan ditimpa oleh berkas tersebut. Nilai sekret tidak ditulis ke log (hanya indikator sumber seperti `environment` atau `repo_dotenv`).

Variabel pengguna secara permanen (contoh dari PowerShell, sesi Anda):

```powershell
[System.Environment]::SetEnvironmentVariable("CURSOR_API_KEY", "ganti-token-anda-di-sini", "User")
```

Keluarkan sesi baru agar Scheduled Task juga melihatnya, atau definisikan kembali dalam dialog **Environment Variables** Windows (Pengguna). Jangan menyalin kunci ke Markdown repo atau dalam commit; berkas `.env` diabaikan oleh Git untuk repo ini tetapi tetap sensitif secara lokal pada disk.

Rujukan: [Headless CLI](https://cursor.com/docs/cli/headless).

## Dependensi Node proyek

Di akar workspace (folder yang berisi `package.json`):

```powershell
cd C:\...\apotek-pos
npm ci
# atau npm install — memakai kunci mana yang digunakan tim Anda
```

## Persiapan branch Git

1. Branch **`cr`** harus ada di `origin` dan berisi pembaruan change request di jalur **`change-request/inbox/*.md`** (lihat checklist untuk format YAML).
2. **Pertama kali** pekerja menciptakan branch kerja **`fu-cr`** dari `origin/cr` jika branch itu belum ada (skrip `cr-runner.ps1` bisa membuat serta push **`fu-cr`** otomatis bila Anda menjalankan run penuh setelah repo bersih dan remote ada).

Konfirmasi remote:

```powershell
git fetch origin
git branch -r
```

Worker akan memeriksa `origin/cr` dan menggabungkan perubahan ke checkout lokal Anda di **`fu-cr`**.

## State proses (`processed-ids`)

Pekerja menyimpan siapa CR yang telah selesai di folder di luar repo (supaya satu `id` tidak diproses ulang oleh kesalahan merge):

```
%LOCALAPPDATA%\apotek-pos-cr-runner\
  processed-ids.json
  runner.lock
```

Kunci tersebut **tidak** diiklankan ke kontrol versi dan **tidak** termasuk oleh `git add` otomatis dalam skrip.

## Log detail jalankan Scheduled Task (`change-request/logs`)

Tiap eksekusi `cr-runner.ps1` (termasuk lewat tugas **`ApotekPosCRRunner`**) menulis **`Start-Transcript`** ke sebuah berkas baru:

```
change-request\logs\cr-runner-yyyyMMdd-HHmmssffffff.log
```

Isinya mencakup salinan aliran PowerShell/host (termasuk sebagian besar output `git`, `npm`, serta `agent` yang masuk konsol pemanggil), sebuah baris awal rangkuman konteks `(Host, PID, parameter)`, serta di akhir konsol Anda akan melihat baris `[DONE]` yang menempelkan **path lengkap** ke berkas log itu.

Ordner `change-request/logs/` diabaikan Git (supaya log tidak tertumpuk ke kontrol versi). Hapus berkas lawas secara berkala jika perlu menjaga kapasitas disk.

## Menjalankan worker

### Sekali jalankan manual (debug)

Pastikan Anda berada pada cabang apa pun tetapi **tidak ada** perubahan terlacak/modifikasi di working tree (skrip gagal cepat kalau pohon tidak bersih, kecuali entri bertanda `??` tidak terlacak saja bisa dihitung boleh—lihat perilaku aktual dalam skrip dalam repo).

```powershell
cd C:\...\apotek-pos
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cr-runner.ps1
```

**Perilaku default** adalah **run penuh** (merge `fu-cr` dengan `origin/cr`, Cursor agent kecuali `-SkipAgent`, `npm lint`/`build`, lalu commit/push bila tepat). **` -DryRun` opsional**, hanya bila Anda ingin melihat daftar inbox tanpa menjalankan alur tersebut.

Parameter berguna:

| Parameter | Makna |
|-----------|-------|
| _(default)_ | Pemanggilan **tanpa** `-DryRun` = jalur lengkap sampai lint/build/(agent)/push sesuai kondisi skrip. |
| `-RepoRoot "C:\path\repo"` | Jika Anda menjalankan skrip dari lokasi lain. |
| `-AgentExe "C:\...\agent.exe"` | Opsional — path lengkap ke executable Cursor CLI; dipakai bila nama `agent` tidak ada di PATH proses tugas. |
| `-DryRun` | Hanya mencetak CR yang akan diantri; tidak merge, tidak panggil `agent`. **Tidak** menguji apakah `npm`/`agent` tersedia di PATH seperti jalur tugas berjadwal penuh (hanya `git`). |
| `-SkipAgent` | Lewati Cursor CLI tetapi tetap `merge`, `lint`, dan `build` (berguna mencoba rantai Git + npm setelah Anda menerapkan perubahan tangan di mesin tes). |
| `-Sandbox` | Menambahkan `--sandbox enabled` kepada `agent`; uji dahulu pada mesin Anda. |

Pastikan **`CURSOR_API_KEY`** tersedia di variabel lingkungan **atau** di **`.env`** akar repo (fallback) saat Anda **tidak** menggunakan `-DryRun` atau `-SkipAgent`.

### Mengantre tiap 10 menit dengan Task Scheduler

Gunakan `schtasks` untuk membuat tugas terjadwal, lalu verifikasi properti tugas di `taskschd.msc`:

```cmd
schtasks /Create /F /TN "ApotekPosCRRunner" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\FULL\PATH\apotek-pos\scripts\cr-runner.ps1 -RepoRoot C:\FULL\PATH\apotek-pos" /SC MINUTE /MO 10 /RL LIMITED
```

Setelah tugas dibuat:
- Buka **Task Scheduler** (`taskschd.msc`) dan pastikan jadwal pengulangan benar (tiap 10 menit).
- Pastikan kolom **Start in (optional)** / direktori awal mengarah ke root repo agar konteks jalur konsisten.
- Jika `agent` tidak ditemukan saat berjalan di Task Scheduler, gunakan parameter `-AgentExe "C:\...\agent.exe"` pada perintah di kolom **Action**.

## Format berkas inbox (singkat)

Taruh sebuah berkas Markdown per CR di **`change-request/inbox/`**, misalnya nama `cart-layout.md`:

```yaml
---
id: cr-2026-0501-cart-layout
title: Susun halaman POS cart
---

## Yang diminta

- Tambahkan ...
```

Field **`id`** wajib stabil dan unik agar sistem tahu CR apa yang sudah selesai.

Contoh siap pakai di repo ini: template dan penjelasan struktur di [`change-request/examples/sample-cr-02.md`](../change-request/examples/sample-cr-02.md) (disarankan disalin ke `change-request/inbox/nama-semantik.md`); contoh isi dengan acceptance criteria di [`change-request/examples/sample-cr-01.md`](../change-request/examples/sample-cr-01.md).

## Troubleshooting

| Gejala | Arah cek |
|--------|----------|
| `agent` tidak dikenali PATH | Restart terminal/System setelah instalasi CLI; jalankan lagi `install` panduan Cursor. Di tugas Terjadwal, jalankan tes `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\cr-runner.ps1` dari repo atau pakai ` -AgentExe` ke executable penuh. |
| Jalur gagal tepat setelah baris Parameter di log, tanpa CURSOR_API_KEY/state | Umumnya `git`, `npm`, atau `agent` tidak ada di PATH proses; cr-runner kini menyegarkan PATH dari registry; pastikan prerequisite terpasang di User atau Machine PATH atau beri ` -AgentExe`. |
| `CURSOR_API_KEY kosong` | Set variabel lingkungan **User** (logoff/login atau restart task) **atau** tambahkan entri `CURSOR_API_KEY=...` di `.env` pada akar repo bila ENV proses masih kosong. |
| `origin/cr` hilang di remote | Pastikan Anda sudah publish branch `cr` ke `origin`. |
| Push ditolak | Periksa kredensial Git, proteksi branch, atau token PAT yang kadaluarsa. |
| Lint/build gagal | Skrip **tidak** menandai CR selesai; perbaiki kode kemudian jalankan lagi worker (atau perbaiki dan commit secara manual tetap konsisten dengan kebijakan tim Anda). |
| Log berhenti setelah pesan lock / tidak ada baris “Lock runner diperoleh” | Bukan pesan error di baris sebelumnya; biasanya **tunggu** instance lain atau cegah paralel. Penjelasan penuh: bagian *Membaca log: state dan lock* di [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md). |

Lihat lagi [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md) sebelum Anda mengaktifkan jadwal tetap pada mesin produksi.
