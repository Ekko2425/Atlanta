-- Atlanta: contenido administrable (tutoriales y actualizaciones)
create table if not exists public.atlanta_tutorials (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  youtube_url text not null,
  created_at timestamptz not null default now()
);
create table if not exists public.atlanta_updates (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text not null default '',
  created_at timestamptz not null default now()
);
alter table public.atlanta_tutorials enable row level security;
alter table public.atlanta_updates enable row level security;
drop policy if exists "Tutorials visible publicly" on public.atlanta_tutorials;
create policy "Tutorials visible publicly" on public.atlanta_tutorials for select using (true);
drop policy if exists "Admins manage tutorials" on public.atlanta_tutorials;
create policy "Admins manage tutorials" on public.atlanta_tutorials for all to authenticated using (public.is_atlanta_admin()) with check (public.is_atlanta_admin());
drop policy if exists "Updates visible publicly" on public.atlanta_updates;
create policy "Updates visible publicly" on public.atlanta_updates for select using (true);
drop policy if exists "Admins manage updates" on public.atlanta_updates;
create policy "Admins manage updates" on public.atlanta_updates for all to authenticated using (public.is_atlanta_admin()) with check (public.is_atlanta_admin());
grant select on public.atlanta_tutorials, public.atlanta_updates to anon, authenticated;
grant insert, update, delete on public.atlanta_tutorials, public.atlanta_updates to authenticated;
