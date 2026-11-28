-- Atlanta DayZ: ampliar a 15 minutos la validez de los códigos de vinculación.
-- Ejecutar una sola vez en Supabase > SQL Editor.
-- No modifica códigos ya generados; los nuevos códigos tendrán 15 minutos de validez.

create or replace function public.create_dayz_link_code()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text;
  v_created_at timestamptz;
begin
  if v_user_id is null then
    raise exception 'Debés iniciar sesión para generar un código.';
  end if;

  if exists (select 1 from public.dayz_player_links l where l.user_id = v_user_id) then
    raise exception 'Esta cuenta ya tiene un BI UID vinculado.';
  end if;

  select c.created_at into v_created_at
  from public.dayz_link_codes c
  where c.user_id = v_user_id;

  if v_created_at is not null and v_created_at > now() - interval '30 seconds' then
    raise exception 'Esperá 30 segundos antes de generar otro código.';
  end if;

  v_code := upper(left(replace(gen_random_uuid()::text, '-', ''), 12));

  insert into public.dayz_link_codes (user_id, token_hash, created_at, expires_at, used_at)
  values (
    v_user_id,
    encode(extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'), 'hex'),
    now(),
    now() + interval '15 minutes',
    null
  )
  on conflict (user_id) do update
    set token_hash = excluded.token_hash,
        created_at = excluded.created_at,
        expires_at = excluded.expires_at,
        used_at = null;

  return v_code;
end;
$$;

revoke all on function public.create_dayz_link_code() from public, anon;
grant execute on function public.create_dayz_link_code() to authenticated;
