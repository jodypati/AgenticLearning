# Checklist operational — CR Runner (Cursor CLI)

Gunakan dokumen bersama panduan instalasi [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md).

## Sebelum pertama kali di production

- [ ] **Node.js & npm**: `node -v`, `npm -v` berfungsi dalam konteks sama dengan Scheduled Task atau layanan Anda.
- [ ] **Git & remote**: `git fetch origin` sukses; branch **`origin/cr`** bisa di-resolve.
- [ ] **Hak akses**: akun pemroses dapat **push** ke **`fu-cr`**.
- [ ] **Cursor CLI**: `agent status`/`agent about` menjawab tidak error; **`CURSOR_API_KEY`** terset melalui Environment Variables (Pengguna/session) **atau** sebagai fallback di **`.env`** di akar repo bila ENV itu kosong (satu baris `CURSOR_API_KEY=...`; jangan mengomit berkas ini ke Git).
- [ ] **Dependensi aplikasi**: `npm ci` (atau pemasangan bersama lain yang disepakati) sekali dalam folder repo.
- [ ] **Konflik paralel**: hanya ada **satu worker** bersamaan; file kunci ada di `%LOCALAPPDATA%\apotek-pos-cr-runner\runner.lock` — jangan jalankan beberapa instance cr-runner paralel secara sengaja pada repo yang sama.
- [ ] **Working tree bersih**: sebelum jalankan lengkap pemrosesan, pohon tidak boleh punya ubahan terlacak yang belum Anda putuskan akarnya (`git status` bersih bagi bagian tracked).
- [ ] Task Scheduler menyetel **pemanggilan sepuluh menit** serta **Working Directory** sama dengan akar repo bila menggunakan template yang disediakan.
- [ ] Pemahaman penyimpanan log: sebuah berkas baru per run di **`change-request/logs/`** (lihat [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md)).

## Membaca log: state dan lock (bukan error)

- **Processed ID di state lokal: N** — jumlah ID change request yang sudah tercatat selesai di berkas state pada mesin itu (Windows: `%LOCALAPPDATA%\apotek-pos-cr-runner\processed-ids.json`; Linux/mac: folder state dari `cr-runner.sh`); **N = 0** wajar jika worker ini belum pernah menyelesaikan CR sukses.
- **INFO: Meminta lock …** — tahap normal sebelum pemrosesan; run yang sehat segera menulis baris **Lock runner diperoleh** (atau setara) berikutnya di log yang sama.
- **Jika log tidak pernah menampilkan baris sukses lock** (terasa macet setelah pesan lock): kemungkinan instance cr-runner lain masih berjalan atau jadwal tugas tumpang tindih pada state directory yang sama (Windows: `%LOCALAPPDATA%\apotek-pos-cr-runner\`; Linux/mac: folder state `apotek-pos-cr-runner`). Tutup proses/worker lain atau sesuaikan jadwal, lalu jalankan lagi. **Jangan** menghapus `runner.lock` / folder `runner.lock.dir` manual kecuali Anda yakin tidak ada proses yang masih memakai lock itu.

## Mengirim sebuah change request (oleh kontributor)

- [ ] Commit dan push Anda ke branch **`cr`** pada remote bersama orang lain.
- [ ] Tambahkan berkas baru di jalur **`change-request/inbox/nama-semantik.md`**.
- [ ] Muat YAML frontmatter paling tidak berisi **`id`** unik dan **`title`**; isi Markdown menjelaskan pekerjaan.
- [ ] Tidak menghapus secara manual sebuah CR pada `fu-cr` secara terburu untuk “memaksa rerun” oleh worker—gunakan **`id` baru** bila Anda perlu revisi struktur yang sama lagi setelah sebuah `id` sudah ada di state pemrosesan lokal sebuah mesin pemrosesan.

Contoh siap pakai: salin struktur dari [`change-request/examples/sample-cr-02.md`](../change-request/examples/sample-cr-02.md) (disarankan untuk berkas inbox baru); untuk pola isi tambahan lihat [`change-request/examples/sample-cr-01.md`](../change-request/examples/sample-cr-01.md). Potongan YAML di [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md) juga tetap valid sebagai ringkasan.

## Setelah salah satu kembalian pemrosesan

- [ ] Cabang **`fu-cr`** mencatat sebuah commit baru yang mengikutkan pesan pola `feat(cr): <id> ...`.
- [ ] Berkas **`%LOCALAPPDATA%\apotek-pos-cr-runner\processed-ids.json`** pada mesin itu berisi **`id`** yang baru selesai (hanya tertulis oleh skrip ketika rantai **`agent`→lint/build→push** bagi CR itu telah sukses, atau jalur tertentu `no staged changes` bila Anda melihat catatan tersebut di log).
- [ ] `npm run lint` dan **`npm run build`** berhasil secara lokal atas snapshot yang baru didorong (cek pipeline CI Anda bila Anda punya salah satu).
- [ ] Jika run gagal: inspeksi log konsol tugas terjadwal; skrip mestinya **tidak** menandai `id` selesai tetapi **mereka** bisa membiarkan pohon bermasalah—buat kebiasaan Anda sendiri antara reset manual (`git`), patch ulang, atau diskusi bersama reviewer.

## Cek menyusul secara berulang-lingkar

| Frekuensi yang disepakati | Apa dicek oleh operator |
|---------------------------|------------------------|
| Setiap beberapa hari | Task Scheduler tidak disable; uptime mesin menyortir kegagalan run terakhir. |
| Sesudah Anda putar Credential | PAT/SSH serta `CURSOR_API_KEY` (ENV atau `.env` lokal) belum kedaluwarsa. |

## Pranala balik cepat trouble

Untuk penyebutan umum gagal seperti PATH, autentikasi, atau `origin/cr` tidak ada silakan gabung lagi ke bagian Troubleshooting panduan utama [CR_RUNNER_INSTALL_WINDOWS.md](CR_RUNNER_INSTALL_WINDOWS.md).
