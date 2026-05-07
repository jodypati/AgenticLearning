# cursor-test-01

Repositori ini berisi aplikasi frontend dan kerangka kerja **change request (CR)** berbasis Markdown plus skrip otomasi Windows untuk memproses antrean CR dengan Cursor CLI.

Lingkup kode aplikasi di sini adalah **frontend saja**: Vite, React, dan TypeScript. Penambahan backend, API server, atau database tidak termasuk lingkup yang disepakati untuk tugas dari `change-request/inbox/` (lihat juga [`.cursor/rules/cr-runner-frontend-only.mdc`](.cursor/rules/cr-runner-frontend-only.mdc)).

## Stack

| Bagian | Teknologi |
|--------|-----------|
| Build & dev server | Vite 8 |
| UI | React 19, TypeScript |
| Kompilasi React | React Compiler (preset Babel lewat `@rolldown/plugin-babel`) |
| Lint | ESLint |

## Prasyarat

- Node.js dan npm (versi yang kompatibel dengan dependensi di `package.json`)

## Mulai cepat

Dari akar repo:

```bash
npm install
npm run dev
```

Perintah lain:

| Skrip | Fungsi |
|-------|--------|
| `npm run build` | Typecheck (`tsc -b`) lalu production build |
| `npm run lint` | ESLint untuk seluruh proyek |
| `npm run preview` | Preview build statis secara lokal |

## Struktur penting

- `src/` — kode sumber aplikasi (`App.tsx`, aset di `src/assets/`).
- `change-request/inbox/` — antrean berkas CR (Markdown + frontmatter YAML: `id`, `title`).
- `change-request/examples/` — contoh format CR.
- `change-request/logs/` — log jalankan [`scripts/cr-runner.ps1`](scripts/cr-runner.ps1) (dibuat per run).
- `scripts/cr-runner.ps1` — worker Windows: sinkron Git (`origin/cr` → checkout `fu-cr`), Cursor CLI `agent`, `npm run lint` / `npm run build`, commit/push sesuai aturan di skrip.
- `docs/` — panduan operasional dan peserta demo, antara lain [`docs/CR_RUNNER_INSTALL_WINDOWS.md`](docs/CR_RUNNER_INSTALL_WINDOWS.md), [`docs/CR_RUNNER_CHECKLIST.md`](docs/CR_RUNNER_CHECKLIST.md), [`docs/01_01_panduan_peserta_demo_windows.md`](docs/01_01_panduan_peserta_demo_windows.md), [`docs/01_02_panduan_peserta_demo_macos.md`](docs/01_02_panduan_peserta_demo_macos.md).

## Change request dan Cursor CLI

1. Kontributor menempatkan berkas baru di `change-request/inbox/` pada branch **`cr`** (ikut kontrak di checklist).
2. Operator menjalankan `cr-runner.ps1` sesuai [`docs/CR_RUNNER_INSTALL_WINDOWS.md`](docs/CR_RUNNER_INSTALL_WINDOWS.md). Autentikasi Cursor: **`CURSOR_API_KEY`** dari environment atau fallback dari `.env` di akar repo (jangan meng-commit kunci tersebut).

Contoh pola isi: [`change-request/examples/sample-cr-01.md`](change-request/examples/sample-cr-01.md), [`change-request/examples/sample-cr-02.md`](change-request/examples/sample-cr-02.md).

## Status aplikasi saat ini

Antarmuka utama masih partir landing Vite/React bawaan; fitur bisnis dikembangkan lewat incremental change request sesuai kebutuhan tim.
