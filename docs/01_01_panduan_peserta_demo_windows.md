# Panduan peserta — demo app (Windows)

Dokumen ini untuk peserta pelatihan yang menjalankan repo demo secara lokal di **Windows**. Alur utama: menyalin repo, menyiapkan Cursor CLI dan kunci API, mengizinkan eksekusi skrip PowerShell, mendaftarkan tugas terjadwal untuk `cr-runner.ps1`, memverifikasi build/dev, lalu mengirim change request di branch **`cr`**.

Untuk panduan instalasi lebih detail dan troubleshooting, lihat [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md) dan [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md). Untuk peserta di **macOS**, gunakan paralel struktur dalam [01_02_panduan_peserta_demo_macos.md](01_02_panduan_peserta_demo_macos.md).

---

## 1. Clone repo dan remote sendiri

1. Clone repo demo ke mesin Anda (URL disesuaikan oleh penyelenggara pelatihan).
2. Untuk bisa bereksperimen dengan Git (push/pull) secara mandiri **tanpa mempengaruhi repo utama**, fork ke akun Anda atau buat repo kosong baru, lalu ubah remote `origin`:

   ```powershell
   cd path\ke\folder-repo
   git remote set-url origin https://github.com/atau/gitlab/.../repo-anda.git
   git remote -v
   ```

   Pastikan Anda punya akses push ke repo tersebut.

---

## 2. Instal Cursor CLI (PowerShell / terminal Cursor)

Jika **PowerShell 7** (`pwsh`) belum terinstal, instal terlebih dahulu.

Cara install (winget, paling mudah; Windows 10 1709+):

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Verifikasi setelah install:

```powershell
pwsh --version
```

Ikuti dokumentasi Cursor untuk pemasangan CLI: [Installation](https://cursor.com/docs/cli/installation).

Setelah terpasang, buka terminal baru (misalnya **PowerShell** di Cursor) dan periksa:

```powershell
agent --version
agent status
```

Jika perintah tidak ditemukan, restart terminal atau pastikan PATH berisi lokasi instalasi Cursor CLI sesuai panduan di atas.

Jika langkah PowerShell berikut gagal karena izin, lihat bagian 4 tentang menjalankan sebagai Administrator.

---

## 3. API key Cursor — simpan sebagai `CURSOR_API_KEY`

1. Buka halaman **Integrations** di Cursor Dashboard: [https://cursor.com/dashboard/integrations](https://cursor.com/dashboard/integrations).
2. Buat atau salin API key yang valid untuk agen CLI (lihat juga referensi: [Headless CLI](https://cursor.com/docs/cli/headless)).
3. Di **akar repo** (folder yang berisi `package.json`), buat atau edit berkas **`.env`** dengan satu baris:

   ```
   CURSOR_API_KEY=isikan-token-anda-di-sini
   ```

   Simpan berkas sebagai **UTF-8**. Berkas `.env` di repo ini sudah dicantumkan di `.gitignore` sehingga tidak ikut commit; **jangan** menempelkan kunci ke dokumentasi atau issue publik.

Script `scripts/cr-runner.ps1` memakai variabel lingkungan `CURSOR_API_KEY`; jika belum ada di ENV proses, skrip dapat membaca nilai dari `.env` di root project.

---

## 4. Execution policy PowerShell (`RemoteSigned`)

**Menjalankan PowerShell sebagai Administrator:** Jika perintah PowerShell di panduan ini ditolak karena izin atau Kebijakan Grup, jalankan **PowerShell** atau **terminal Cursor** sebagai Administrator (klik kanan ikon PowerShell / Terminal → **Run as administrator**), lalu ulangi perintah. Untuk `Set-ExecutionPolicy` dengan scope **CurrentUser** di bawah biasanya cukup jendela biasa; jendela yang dinaikkan (elevated) berguna bila IT memaksa kebijakan tingkat mesin atau Anda mendapat pesan akses ditolak.

Agar skrip lokal dapat dijalankan dengan nyaman (termasuk `cr-runner.ps1`), di PowerShell jalankan:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

Pada prompt konfirmasi, pilih **Yes [Y]** (atau ketik `Y`).

---

## 5. Task Scheduler — jalankan CR runner tiap 5 menit

**Penting:** Ganti **`C:\Path\Ke\RepoAnda`** di bawah dengan path absolut folder clone repo Anda. Contoh struktur repo: ada `scripts\cr-runner.ps1` di dalam folder tersebut.

Jalankan perintah berikut dari **Command Prompt (`cmd.exe`)**:

```cmd
schtasks /Create /F /TN "CRRunner" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Path\Ke\RepoAnda\scripts\cr-runner.ps1 -RepoRoot C:\Path\Ke\RepoAnda" /SC MINUTE /MO 5 /RL LIMITED
```

Jika ada spasi pada folder name, gunakan contoh berikut:

```cmd
schtasks /Create /F /TN "CRRunner" /TR "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\De\Temporary Project\cursor-test-01\scripts\cr-runner.ps1\" -RepoRoot \"C:\De\Temporary Project\cursor-test-01\"" /SC MINUTE /MO 5 /RL LIMITED
```

- Task name: **`CRRunner`**
- Interval: setiap **5 menit**

**Menghapus tugas** (jika perlu mengulang pendaftaran):

```cmd
schtasks /Delete /TN "CRRunner" /F
```

Anda juga dapat mengedit atau menonaktifkan tugas lewat **`taskschd.msc`** (Task Scheduler GUI).

Setelah membuat tugas dengan `schtasks`, buka **`taskschd.msc`** untuk memastikan kolom **Start in (optional)** / direktori awal menunjuk ke root repo agar eksekusi konsisten. Rujukan detail tetap ada di [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md).

---

## 6. Dependensi npm, build, dan dev server

Di folder akar repo:

```powershell
cd C:\Path\Ke\RepoAnda
npm install
```

Verifikasi build tanpa error (sesuai gate yang dipakai worker):

```powershell
npm run build
```

Untuk memastikan aplikasi bisa dijalankan di mode pengembangan, jalankan:

```powershell
npm run dev
```

Buka URL yang dicetak Vite di browser untuk cek cepat lalu **hentikan server** dengan **Ctrl+C** di terminal (proses ini interaktif dan tidak untuk dibiarkan menggantung jika Anda hanya mengecek sekali).

---

## 7. Branch `cr`, berkas inbox, dan push

1. Checkout atau buat branch **`cr`** (dan pastikan ada di remote jika dibutuhkan alur bersama pelatihan).

   ```powershell
   git checkout -b cr
   # atau: git checkout cr && git pull
   ```

2. Tambahkan **satu berkas baru** Markdown di folder **`change-request/inbox/`** dengan nama bermakna (misalnya `cr-2026-0501-latihan-saya.md`).

3. **Struktur isi CR:** salin pola dari **[`change-request/examples/sample-cr-02.md`](../change-request/examples/sample-cr-02.md)** (frontmatter YAML wajib memuat **`id`** unik stabil dan **`title`**). Untuk pola acceptance criteria konkret tambahan, rujuk **[`change-request/examples/sample-cr-01.md`](../change-request/examples/sample-cr-01.md)**.

4. Commit dan push ke remote pada branch **`cr`** bersama berkas tersebut:

   ```powershell
   git add change-request/inbox/nama-file-anda.md
   git commit -m "feat(cr): tambah inbox latihan peserta"
   git push origin cr
   ```

---

## Rujukan singkat

| Topik | Dokumen |
|--------|---------|
| Instalasi runner, PATH, Scheduled Task lebih detail | [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md) |
| Checklist operasional & pengiriman CR | [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md) |
| Template struktur CR (disalin ke inbox) | [sample-cr-02.md](../change-request/examples/sample-cr-02.md) |
| Contoh isi CR | [sample-cr-01.md](../change-request/examples/sample-cr-01.md) |
| Peserta macOS | [01_02_panduan_peserta_demo_macos.md](01_02_panduan_peserta_demo_macos.md) |
