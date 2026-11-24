-- Atlanta DayZ: administración segura de rangos VIP.
-- Ejecutar una vez en Supabase > SQL Editor > New query.
-- Después, agregar manualmente el primer administrador (ver ADMIN-VIP.md).

create table if not exists public.atlanta_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.atlanta_admins enable row level security;
revoke all on table public.atlanta_admins from anon, authenticated;

create or replace function public.is_atlanta_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.atlanta_admins a
    where a.user_id = (select auth.uid())
  );
$$;

create or replace function public.admin_list_players()
returns table (
  id uuid,
  username text,
  steam_id text,
  vip_rank text,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_atlanta_admin() then
    raise exception 'No autorizado: se requiere rol de administrador.';
  end if;

  return query
    select p.id, p.username, p.steam_id, p.vip_rank, p.created_at
    from public.profiles p
    order by p.username asc;
end;
$$;

create or replace function public.admin_set_vip(
  p_user_id uuid,
  p_vip_rank text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_atlanta_admin() then
    raise exception 'No autorizado: se requiere rol de administrador.';
  end if;

  if p_vip_rank is null or p_vip_rank not in (
    'Sin VIP', 'VIP Bronce', 'VIP Plata', 'VIP Oro', 'VIP Diamante', 'VIP Leyenda'
  ) then
    raise exception 'Rango VIP no válido.';
  end if;

  update public.profiles
     set vip_rank = p_vip_rank
   where id = p_user_id;

  if not found then
    raise exception 'No se encontró el jugador.';
  end if;
end;
$$;

revoke all on function public.is_atlanta_admin() from public, anon;
revoke all on function public.admin_list_players() from public, anon;
revoke all on function public.admin_set_vip(uuid, text) from public, anon;
grant execute on function public.is_atlanta_admin() to authenticated;
grant execute on function public.admin_list_players() to authenticated;
grant execute on function public.admin_set_vip(uuid, text) to authenticated;
