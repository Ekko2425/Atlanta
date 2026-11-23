-- Atlanta DayZ: ampliación segura de perfiles.
-- Ejecutar una vez en Supabase > SQL Editor > New query.
-- No elimina perfiles ni cuentas existentes.

alter table public.profiles
  add column if not exists avatar_path text,
  add column if not exists steam_id text,
  add column if not exists bio text not null default '',
  add column if not exists vip_rank text not null default 'Sin VIP',
  add column if not exists kills integer,
  add column if not exists deaths integer,
  add column if not exists playtime_hours numeric(10,1);

alter table public.profiles
  add constraint profiles_steam_id_format
  check (steam_id is null or steam_id ~ '^[0-9]{17}$');

alter table public.profiles
  add constraint profiles_bio_length
  check (char_length(bio) <= 240);

alter table public.profiles
  add constraint profiles_vip_rank_length
  check (char_length(vip_rank) between 1 and 40);

alter table public.profiles
  add constraint profiles_stats_nonnegative
  check (
    (kills is null or kills >= 0) and
    (deaths is null or deaths >= 0) and
    (playtime_hours is null or playtime_hours >= 0)
  );

create unique index if not exists profiles_steam_id_unique
  on public.profiles (steam_id)
  where steam_id is not null;

-- Los jugadores pueden editar únicamente sus datos personales.
-- VIP y estadísticas quedan reservados para un proceso administrativo/servidor confiable.
revoke update on table public.profiles from authenticated;
grant select on table public.profiles to authenticated;
grant update (username, steam_id, bio, avatar_path)
  on table public.profiles to authenticated;

-- Bucket público para mostrar avatares; la escritura sigue limitada al dueño.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'atlanta-avatars',
  'atlanta-avatars',
  true,
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Atlanta avatars are publicly viewable" on storage.objects;
create policy "Atlanta avatars are publicly viewable"
  on storage.objects for select
  to public
  using (bucket_id = 'atlanta-avatars');

drop policy if exists "Players upload their own Atlanta avatar" on storage.objects;
create policy "Players upload their own Atlanta avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'atlanta-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Players update their own Atlanta avatar" on storage.objects;
create policy "Players update their own Atlanta avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'atlanta-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'atlanta-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists "Players delete their own Atlanta avatar" on storage.objects;
create policy "Players delete their own Atlanta avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'atlanta-avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );
