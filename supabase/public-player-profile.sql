-- Atlanta DayZ: lectura pública y limitada de perfiles.
-- Ejecutar una vez en Supabase > SQL Editor > New query.
-- Solo expone datos del perfil comunitario; nunca correo ni datos de Auth.

create or replace function public.get_public_player_profile(p_user_id uuid)
returns table (
  id uuid,
  username text,
  created_at timestamptz,
  avatar_path text,
  steam_id text,
  bio text,
  vip_rank text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    p.id,
    p.username,
    p.created_at,
    p.avatar_path,
    p.steam_id,
    p.bio,
    p.vip_rank
  from public.profiles p
  where p.id = p_user_id
  limit 1;
$$;

revoke all on function public.get_public_player_profile(uuid) from public;
grant execute on function public.get_public_player_profile(uuid) to anon, authenticated;
