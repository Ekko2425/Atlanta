-- Atlanta DayZ: lista de amigos de la comunidad.
-- Ejecutar una vez en Supabase > SQL Editor > New query.
-- No elimina usuarios ni perfiles.

create table if not exists public.friend_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references auth.users(id) on delete cascade,
  addressee_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending'
    check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  constraint friend_requests_not_self check (requester_id <> addressee_id)
);

create unique index if not exists friend_requests_unique_pair
  on public.friend_requests (
    least(requester_id, addressee_id),
    greatest(requester_id, addressee_id)
  );

create index if not exists friend_requests_addressee_status_idx
  on public.friend_requests (addressee_id, status);

alter table public.friend_requests enable row level security;

drop policy if exists "Users can view their own friend requests" on public.friend_requests;
create policy "Users can view their own friend requests"
  on public.friend_requests for select
  to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

drop policy if exists "Users can send their own friend requests" on public.friend_requests;
create policy "Users can send their own friend requests"
  on public.friend_requests for insert
  to authenticated
  with check (
    requester_id = (select auth.uid())
    and addressee_id <> (select auth.uid())
    and status = 'pending'
  );

drop policy if exists "Recipients can accept friend requests" on public.friend_requests;
create policy "Recipients can accept friend requests"
  on public.friend_requests for update
  to authenticated
  using (addressee_id = (select auth.uid()) and status = 'pending')
  with check (addressee_id = (select auth.uid()) and status = 'accepted');

drop policy if exists "Participants can remove requests or friendships" on public.friend_requests;
create policy "Participants can remove requests or friendships"
  on public.friend_requests for delete
  to authenticated
  using (
    requester_id = (select auth.uid())
    or addressee_id = (select auth.uid())
  );

grant select, insert, delete on public.friend_requests to authenticated;
grant update (status) on public.friend_requests to authenticated;

-- La búsqueda de jugadores necesita que los miembros autenticados puedan
-- ver los campos públicos de los perfiles, nunca el correo de Auth.
drop policy if exists "Authenticated users can view community profiles" on public.profiles;
create policy "Authenticated users can view community profiles"
  on public.profiles for select
  to authenticated
  using (true);

-- Las estadísticas del servidor ya no forman parte del perfil.
alter table public.profiles
  drop column if exists kills,
  drop column if exists deaths,
  drop column if exists playtime_hours;
