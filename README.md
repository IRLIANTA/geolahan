# GeoLahan - WebGIS Pembukaan Lahan (Admin)

WebGIS khusus admin untuk laporan pembukaan lahan: polygon, titik, garis, multi-geometri, TIN.
Stack: HTML/JS + Leaflet + Turf.js, Supabase (Postgres + PostGIS + Auth), hosting Vercel.

## Struktur
```
index.html          UI (Beranda, About, 5 halaman CRUD)
js/config.js        URL Supabase + publishable key
supabase/schema.sql skema database, trigger, RLS
```

## Langkah setup

### 1. GitHub
```
git init
git add .
git commit -m "feat: UI awal GeoLahan"
git branch -M main
git remote add origin https://github.com/USERNAME/geolahan.git
git push -u origin main
```
(Buat dulu repo kosong bernama `geolahan` di github.com.)

### 2. Supabase
1. Buat project baru (pilih region terdekat, mis. Singapore). Simpan password database.
2. SQL Editor > New query > tempel isi `supabase/schema.sql` > Run.
3. Authentication > Users > Add user (email + password Anda).
4. Jalankan `insert into public.admin_users ...` (ada di bagian bawah schema.sql) dengan email Anda.
5. Matikan pendaftaran publik di pengaturan Authentication (cari "Allow new users to sign up"), karena ini aplikasi admin.

### 3. Hubungkan kode
Settings > API Keys > salin **Project URL** dan **Publishable key** (`sb_publishable_...`) ke `js/config.js`.
Secret key / service_role tidak boleh masuk repo atau kode browser.

### 4. Vercel
Import repo dari GitHub > Framework Preset: Other > Deploy.
Setelah dapat domain `*.vercel.app`, daftarkan di Supabase: Authentication > URL Configuration (Site URL).

## Status
- [x] UI statis dengan data contoh (localStorage)
- [ ] Login Supabase Auth
- [ ] CRUD ke tabel `features` + `desa`
- [ ] Gambar langsung di peta (Leaflet.draw)
- [ ] Tracking GPS, import drone, export
