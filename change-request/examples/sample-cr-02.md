---
id: cr-2026-0501-contoh-cart-widget
title: Contoh CR - widget ringkasan keranjang di header
---

Ini adalah **contoh struktur** change request. Untuk digunakan sungguhan: salin struktur ini ke `change-request/inbox/nama-semantik.md` pada branch `cr`, sesuaikan `id`, `title`, dan isinya, lalu push. Field `id` harus stabil dan **unik** agar tidak diproses dua kali.

## Konteks singkat

- Halaman utama POS akan menambah indikasi jumlah item di keranjang.

## Acceptance criteria

- [ ] Badge atau teks ringkas di bagian atas (header) yang menampilkan jumlah item (mock boleh).
- [ ] Responsif seperti layout aplikasi lain di halaman tersebut.
- [ ] Tidak menambahkan API/backend; pakai dummy state lokal atau context jika diperlukan.

## Catatan desain / referensi

- Gunakan pola warna/font yang sama dengan halaman utama yang ada sekarang.

## Out of scope

- Persistensi keranjang ke server.
- Integrasi pembayaran.
