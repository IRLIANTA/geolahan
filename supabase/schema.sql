-- =====================================================================
-- GeoLahan - skema awal (Supabase + PostGIS)
-- Jalankan di Supabase Dashboard > SQL Editor.
-- Akses: HANYA admin (baris di public.admin_users). anon tidak punya akses.
-- =====================================================================

create extension if not exists postgis with schema extensions;

-- ---------- Tabel ----------

create table public.admin_users (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.desa (
  id         bigint generated always as identity primary key,
  nama       text not null unique,
  kecamatan  text,
  kabupaten  text,
  created_at timestamptz not null default now()
);

-- Satu tabel untuk 5 modul: polygon, point, line, multi, tin
create table public.features (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('polygon','point','line','multi','tin')),
  nama        text not null,
  desa_id     bigint references public.desa (id) on delete set null,
  status      text not null default 'Draft' check (status in ('Draft','Diverifikasi','Selesai')),
  ket         text,
  geom        extensions.geometry(Geometry, 4326) not null,
  titik_tin   extensions.geometry(MultiPoint, 4326),   -- titik sumber untuk TIN
  luas_ha     numeric(14,4) not null default 0,         -- diisi trigger
  panjang_m   numeric(14,2) not null default 0,         -- diisi trigger
  keliling_m  numeric(14,2) not null default 0,         -- diisi trigger
  created_by  uuid default auth.uid() references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  constraint geom_valid check (extensions.st_isvalid(geom)),
  constraint geom_sesuai_kind check (
       (kind = 'polygon' and extensions.geometrytype(geom) = 'POLYGON')
    or (kind = 'point'   and extensions.geometrytype(geom) = 'POINT')
    or (kind = 'line'    and extensions.geometrytype(geom) = 'LINESTRING')
    or (kind = 'multi'   and extensions.geometrytype(geom) in ('MULTIPOINT','MULTILINESTRING','MULTIPOLYGON'))
    or (kind = 'tin'     and extensions.geometrytype(geom) = 'GEOMETRYCOLLECTION')
  )
);

-- ---------- Index ----------

create index features_geom_gix        on public.features using gist (geom);
create index features_desa_idx        on public.features (desa_id);
create index features_kind_status_idx on public.features (kind, status);

-- ---------- Trigger: hitung luas / panjang / keliling otomatis ----------

create function public.set_ukuran() returns trigger
language plpgsql
set search_path = ''
as $$
declare
  t text := extensions.geometrytype(new.geom);
begin
  new.luas_ha := 0; new.panjang_m := 0; new.keliling_m := 0;

  if new.kind = 'tin' then
    -- TIN: jumlahkan luas semua segitiga
    select coalesce(sum(extensions.st_area(d.geom::extensions.geography)), 0) / 10000
      into new.luas_ha
      from extensions.st_dump(new.geom) d;
  elsif t in ('POLYGON','MULTIPOLYGON') then
    new.luas_ha    := extensions.st_area(new.geom::extensions.geography) / 10000;
    new.keliling_m := extensions.st_perimeter(new.geom::extensions.geography);
  elsif t in ('LINESTRING','MULTILINESTRING') then
    new.panjang_m  := extensions.st_length(new.geom::extensions.geography);
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke execute on function public.set_ukuran() from public, anon, authenticated;

create trigger features_set_ukuran
before insert or update on public.features
for each row execute function public.set_ukuran();

-- ---------- Row Level Security (admin only) ----------

alter table public.admin_users enable row level security;
alter table public.desa        enable row level security;
alter table public.features    enable row level security;

-- admin hanya boleh membaca barisnya sendiri (dipakai untuk cek peran di policy lain)
create policy "admin_users: baca baris sendiri" on public.admin_users
  for select to authenticated
  using (user_id = (select auth.uid()));

-- desa
create policy "desa: admin select" on public.desa for select to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "desa: admin insert" on public.desa for insert to authenticated
  with check (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "desa: admin update" on public.desa for update to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "desa: admin delete" on public.desa for delete to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));

-- features
create policy "features: admin select" on public.features for select to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "features: admin insert" on public.features for insert to authenticated
  with check (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "features: admin update" on public.features for update to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())))
  with check (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));
create policy "features: admin delete" on public.features for delete to authenticated
  using (exists (select 1 from public.admin_users a where a.user_id = (select auth.uid())));

-- ---------- Hak akses Data API ----------

revoke all on public.admin_users, public.desa, public.features from anon;
grant select                         on public.admin_users to authenticated;
grant select, insert, update, delete on public.desa, public.features to authenticated;

-- ---------- View statistik untuk Beranda (security_invoker = ikut RLS) ----------

create view public.v_statistik with (security_invoker = true) as
select
  count(*)                                           as total_objek,
  count(*) filter (where kind = 'polygon')           as jumlah_polygon,
  count(*) filter (where kind = 'point')             as jumlah_titik,
  count(*) filter (where kind = 'line')              as jumlah_garis,
  count(*) filter (where kind = 'multi')             as jumlah_multi,
  count(*) filter (where kind = 'tin')               as jumlah_tin,
  count(distinct desa_id)                            as jumlah_desa,
  coalesce(sum(luas_ha)   filter (where kind in ('polygon','multi')), 0) as total_luas_ha,
  coalesce(sum(panjang_m) filter (where kind in ('line','multi')), 0)    as total_panjang_m,
  count(*) filter (where status = 'Selesai')         as jumlah_selesai
from public.features;

create view public.v_per_desa with (security_invoker = true) as
select d.id, d.nama,
       count(f.id) as jumlah_objek,
       coalesce(sum(f.luas_ha) filter (where f.kind in ('polygon','multi')), 0) as luas_ha
from public.desa d
left join public.features f on f.desa_id = d.id
group by d.id, d.nama;

revoke all on public.v_statistik, public.v_per_desa from anon;
grant select on public.v_statistik, public.v_per_desa to authenticated;

-- ---------- Jadikan akun Anda admin ----------
-- 1) Buat user: Dashboard > Authentication > Users > Add user (email + password)
-- 2) Ganti email di bawah, lalu jalankan:
--
-- insert into public.admin_users (user_id)
-- select id from auth.users where email = 'EMAIL_ANDA@contoh.com';
