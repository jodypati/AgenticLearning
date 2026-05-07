# Panduan peserta — demo app (macOS)

Dokumen ini untuk peserta pelatihan yang menjalankan repo demo secara lokal di **macOS**. Alur utama: menyalin repo, menyiapkan Cursor CLI dan kunci API, memverifikasi build/dev, lalu mengirim change request di branch **`cr`**. Penjadwalan otomatis untuk worker Bash ([`scripts/cr-runner.sh`](../scripts/cr-runner.sh)) bersifat opsional.

Untuk checklist operasional dan format CR, lihat [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md). Detail instalasi worker di Windows ada di [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md) (referensi lintas platform). Panduan paralel untuk Windows: [01_01_panduan_peserta_demo_windows.md](01_01_panduan_peserta_demo_windows.md).

---

## 1. Clone repo dan remote sendiri

1. Clone repo demo ke mesin Anda (URL disesuaikan oleh penyelenggara pelatihan).
2. Untuk bisa bereksperimen dengan Git (push/pull) secara mandiri **tanpa mempengaruhi repo utama**, fork ke akun Anda atau buat repo kosong baru, lalu ubah remote `origin`:

   ```bash
   cd /path/ke/folder-repo
   git remote set-url origin https://github.com/atau/gitlab/.../repo-anda.git
   git remote -v
   ```

   Pastikan Anda punya akses push ke repo tersebut.

---

## 2. Instal Cursor CLI (Terminal di Cursor atau Terminal.app)

Ikuti dokumentasi Cursor untuk pemasangan CLI: [Installation](https://cursor.com/docs/cli/installation).

Setelah terpasang, buka terminal baru dan periksa:

```bash
agent --version
agent status
```

Jika perintah tidak ditemukan, restart terminal atau pastikan PATH berisi lokasi instalasi Cursor CLI sesuai panduan di atas.

---

## 3. API key Cursor — simpan sebagai `CURSOR_API_KEY`

1. Buka halaman **Integrations** di Cursor Dashboard: [https://cursor.com/dashboard/integrations](https://cursor.com/dashboard/integrations).
2. Buat atau salin API key yang valid untuk agen CLI (lihat juga referensi: [Headless CLI](https://cursor.com/docs/cli/headless)).
3. Di **akar repo** (folder yang berisi `package.json`), buat atau edit berkas **`.env`** dengan satu baris:

   ```
   CURSOR_API_KEY=isikan-token-anda-di-sini
   ```

   Simpan berkas sebagai **UTF-8**. Berkas `.env` di repo ini sudah dicantumkan di `.gitignore` sehingga tidak ikut commit; **jangan** menempelkan kunci ke dokumentasi atau issue publik.

Skrip [`scripts/cr-runner.sh`](../scripts/cr-runner.sh) memakai variabel lingkungan `CURSOR_API_KEY`; jika belum ada di ENV proses, skrip dapat membaca nilai dari `.env` di root project. Skrip memerlukan **Python 3** (biasanya sudah ada di macOS) untuk membaca state JSON dan frontmatter.

---

## 4. Terminal, izin, dan Cursor

Di macOS **tidak** ada padanan wajib untuk `Set-ExecutionPolicy` seperti di Windows. Yang umum dipastikan peserta:

- Jalankan `git`, `npm`, `python3`, dan `agent` dari **Terminal** (integrasi terminal Cursor atau Terminal.app) agar PATH konsisten.
- Jika macOS memblokir pembukaan aplikasi saat pertama kali, atur lewat **System Settings → Privacy & Security** sesuai petunjuk Apple, atau klik kanan Cursor → **Open** untuk langkah percaya awal.

---

## 5. Penjadwalan — jalankan CR runner tiap 5 menit (opsional)

Worker untuk macOS adalah skrip Bash: [`scripts/cr-runner.sh`](../scripts/cr-runner.sh). Untuk Windows, gunakan panduan Task Scheduler di [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md); di macOS gunakan cara di bawah.

**Prasyarat:** `git`, `python3`, dan untuk run penuh juga `npm` serta `agent` di PATH (skrip menambahkan `/opt/homebrew/bin` dan `/usr/local/bin` di awal PATH untuk membantu lingkungan terjadwal).

**Penting:** Ganti **`/path/ke/RepoAnda`** dengan path absolut folder clone Anda (misalnya `/Users/namaAnda/proyek/cursor-demo`). Di dalamnya harus ada `scripts/cr-runner.sh`.

Jadikan skrip dapat dieksekusi (sekali):

```bash
chmod +x /path/ke/RepoAnda/scripts/cr-runner.sh
```

Uji antrean inbox tanpa merge, agent, atau push:

```bash
cd /path/ke/RepoAnda
./scripts/cr-runner.sh --repo-root "$(pwd)" --dry-run
```

Skrip menyimpan berkas state (misalnya processed IDs dan kunci penguncian) **di luar repo**, biasanya di **`~/Library/Application Support/apotek-pos-cr-runner/`**. Jika proses terhenti mendadak, folder lock `runner.lock.dir` di sana bisa tertinggal; jika tidak ada proses lain yang berjalan, hapus manual: `rmdir ~/Library/Application\ Support/apotek-pos-cr-runner/runner.lock.dir`.

### Opsi A: `launchd` (LaunchAgent)

1. Buat berkas plist, misalnya `~/Library/LaunchAgents/com.demo.cr-runner.plist`, dengan isi berikut (sesuaikan path repo dan label jika bentrok):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.demo.cr-runner</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/path/ke/RepoAnda/scripts/cr-runner.sh</string>
    <string>--repo-root</string>
    <string>/path/ke/RepoAnda</string>
  </array>
  <key>WorkingDirectory</key>
  <string>/path/ke/RepoAnda</string>
  <key>StartInterval</key>
  <integer>300</integer>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
```

2. Muat dan mulai:

```bash
launchctl load ~/Library/LaunchAgents/com.demo.cr-runner.plist
```

3. Berhenti dan lepas (misalnya untuk mengulang konfigurasi):

```bash
launchctl unload ~/Library/LaunchAgents/com.demo.cr-runner.plist
```

### Opsi B: `cron`

Lingkungan `cron` sering punya PATH minimal; gunakan path absolut ke skrip dan repo.

```bash
crontab -e
```

Contoh baris (setiap 5 menit):

```
*/5 * * * * /bin/bash /path/ke/RepoAnda/scripts/cr-runner.sh --repo-root /path/ke/RepoAnda >> /tmp/cr-runner-cron.log 2>&1
```

---

## 6. Dependensi npm, build, dan dev server

Di folder akar repo:

```bash
cd /path/ke/RepoAnda
npm install
```

Verifikasi build tanpa error (sesuai gate yang dipakai worker):

```bash
npm run build
```

Untuk memastikan aplikasi bisa dijalankan di mode pengembangan:

```bash
npm run dev
```

Buka URL yang dicetak Vite di browser untuk cek cepat lalu **hentikan server** dengan **Ctrl+C** di terminal (proses ini interaktif dan tidak untuk dibiarkan menggantung jika Anda hanya mengecek sekali).

---

## 7. Branch `cr`, berkas inbox, dan push

1. Checkout atau buat branch **`cr`** (dan pastikan ada di remote jika dibutuhkan alur bersama pelatihan).

   ```bash
   git checkout -b cr
   # atau: git checkout cr && git pull
   ```

2. Tambahkan **satu berkas baru** Markdown di folder **`change-request/inbox/`** dengan nama bermakna (misalnya `cr-2026-0501-latihan-saya.md`).

3. **Struktur isi CR:** salin pola dari **[`change-request/examples/sample-cr-02.md`](../change-request/examples/sample-cr-02.md)** (frontmatter YAML wajib memuat **`id`** unik stabil dan **`title`**). Untuk pola acceptance criteria konkret tambahan, rujuk **[`change-request/examples/sample-cr-01.md`](../change-request/examples/sample-cr-01.md)**.

4. Commit dan push ke remote pada branch **`cr`** bersama berkas tersebut:

   ```bash
   git add change-request/inbox/nama-file-anda.md
   git commit -m "feat(cr): tambah inbox latihan peserta"
   git push origin cr
   ```

---

## Rujukan singkat

| Topik | Dokumen |
|--------|---------|
| Instalasi runner & Task Scheduler (Windows, referensi) | [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md) |
| Checklist operasional & pengiriman CR | [CR_RUNNER_CHECKLIST.md](CR_RUNNER_CHECKLIST.md) |
| Template struktur CR (disalin ke inbox) | [sample-cr-02.md](../change-request/examples/sample-cr-02.md) |
| Contoh isi CR | [sample-cr-01.md](../change-request/examples/sample-cr-01.md) |
| Peserta Windows | [01_01_panduan_peserta_demo_windows.md](01_01_panduan_peserta_demo_windows.md) |
| Worker Bash (macOS/Linux) | [cr-runner.sh](../scripts/cr-runner.sh) |
