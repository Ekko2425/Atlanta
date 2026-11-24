-- Atlanta DayZ: base segura para vinculación BI UID y lectura de ADM.
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor.
-- No modifica profiles ni las funciones existentes de cuentas.

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.dayz_player_links (
  user_id uuid primary key references auth.users(id) on delete cascade,
  bi_uid text not null unique
    check (char_length(bi_uid) = 44 and bi_uid ~ '^[A-Za-z0-9_=-]{44}$'),
  verified_at timestamptz not null default now()
);

create table if not exists public.dayz_link_codes (
  user_id uuid primary key references auth.users(id) on delete cascade,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  used_at timestamptz
);

create table if not exists public.dayz_events (
  id bigint generated always as identity primary key,
  event_key text not null unique,
  event_type text not null,
  occurred_at timestamp without time zone,
  player_uid text,
  actor_uid text,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now()
);

create index if not exists dayz_events_player_time_idx
  on public.dayz_events (player_uid, occurred_at desc);
create index if not exists dayz_events_actor_time_idx
  on public.dayz_events (actor_uid, occurred_at desc);
create index if not exists dayz_events_type_time_idx
  on public.dayz_events (event_type, occurred_at desc);

create table if not exists public.dayz_file_cursors (
  file_path text primary key,
  byte_offset bigint not null default 0 check (byte_offset >= 0),
  updated_at timestamptz not null default now()
);

create table if not exists public.dayz_achievement_definitions (
  achievement_key text primary key,
  name text not null,
  description text not null,
  rule jsonb not null default '{}'::jsonb,
  active boolean not null default true
);

create table if not exists public.dayz_player_achievements (
  user_id uuid not null references auth.users(id) on delete cascade,
  achievement_key text not null references public.dayz_achievement_definitions(achievement_key) on delete cascade,
  progress bigint not null default 0 check (progress >= 0),
  unlocked_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, achievement_key)
);

alter table public.dayz_player_links enable row level security;
alter table public.dayz_link_codes enable row level security;
alter table public.dayz_events enable row level security;
alter table public.dayz_file_cursors enable row level security;
alter table public.dayz_achievement_definitions enable row level security;
alter table public.dayz_player_achievements enable row level security;

drop policy if exists "Players can view their own DayZ link" on public.dayz_player_links;
create policy "Players can view their own DayZ link"
  on public.dayz_player_links for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Authenticated users can view achievement definitions" on public.dayz_achievement_definitions;
create policy "Authenticated users can view achievement definitions"
  on public.dayz_achievement_definitions for select to authenticated
  using (active = true);

drop policy if exists "Players can view their own achievements" on public.dayz_player_achievements;
create policy "Players can view their own achievements"
  on public.dayz_player_achievements for select to authenticated
  using (auth.uid() = user_id);

-- Ningún usuario puede escribir directamente en tablas de vinculación,
-- eventos, cursores o logros. Las escrituras se hacen desde funciones seguras.
revoke all on public.dayz_player_links, public.dayz_link_codes,
  public.dayz_events, public.dayz_file_cursors,
  public.dayz_achievement_definitions, public.dayz_player_achievements
  from anon, authenticated;

grant select on public.dayz_player_links,
  public.dayz_achievement_definitions,
  public.dayz_player_achievements to authenticated;

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

  v_code := upper(left(replace(gen_random_uuid()::text, '-', ''), 8));

  insert into public.dayz_link_codes (user_id, token_hash, created_at, expires_at, used_at)
  values (
    v_user_id,
    encode(extensions.digest(convert_to(v_code, 'UTF8'), 'sha256'), 'hex'),
    now(),
    now() + interval '10 minutes',
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

-- Solo el procesador de ADM (service_role) puede confirmar una vinculación.
-- La función no devuelve ni registra el código ni el UID en texto de respuesta.
create or replace function public.dayz_confirm_link(p_code text, p_bi_uid text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code public.dayz_link_codes%rowtype;
  v_existing_uid text;
  v_existing_user uuid;
  v_hash text;
begin
  if p_code is null or p_code !~ '^[A-Fa-f0-9]{8}$'
     or p_bi_uid is null
     or char_length(p_bi_uid) <> 44
     or p_bi_uid !~ '^[A-Za-z0-9_=-]{44}$' then
    return jsonb_build_object('ok', false, 'reason', 'invalid_format');
  end if;

  v_hash := encode(extensions.digest(convert_to(upper(p_code), 'UTF8'), 'sha256'), 'hex');

  select * into v_code
  from public.dayz_link_codes
  where token_hash = v_hash
  for update;

  if not found or v_code.used_at is not null or v_code.expires_at <= now() then
    return jsonb_build_object('ok', false, 'reason', 'invalid_or_expired');
  end if;

  select l.bi_uid into v_existing_uid
  from public.dayz_player_links l
  where l.user_id = v_code.user_id;

  if v_existing_uid is not null then
    update public.dayz_link_codes set used_at = now() where user_id = v_code.user_id;
    if v_existing_uid = p_bi_uid then
      return jsonb_build_object('ok', true, 'reason', 'already_linked');
    end if;
    return jsonb_build_object('ok', false, 'reason', 'account_already_linked');
  end if;

  select l.user_id into v_existing_user
  from public.dayz_player_links l
  where l.bi_uid = p_bi_uid;

  if v_existing_user is not null then
    update public.dayz_link_codes set used_at = now() where user_id = v_code.user_id;
    return jsonb_build_object('ok', false, 'reason', 'uid_already_linked');
  end if;

  insert into public.dayz_player_links (user_id, bi_uid)
  values (v_code.user_id, p_bi_uid);

  update public.dayz_link_codes set used_at = now() where user_id = v_code.user_id;

  return jsonb_build_object('ok', true, 'reason', 'linked');
end;
$$;

revoke all on function public.dayz_confirm_link(text, text) from public, anon, authenticated;
grant execute on function public.dayz_confirm_link(text, text) to service_role;

-- Inserción idempotente de eventos y avance de cursores en una sola transacción.
create or replace function public.dayz_ingest_batch(p_events jsonb, p_cursors jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_inserted integer := 0;
  v_cursor_count integer := 0;
begin
  insert into public.dayz_events (
    event_key, event_type, occurred_at, player_uid, actor_uid, payload
  )
  select
    x.event_key, x.event_type, x.occurred_at, x.player_uid, x.actor_uid,
    coalesce(x.payload, '{}'::jsonb)
  from jsonb_to_recordset(coalesce(p_events, '[]'::jsonb)) as x(
    event_key text,
    event_type text,
    occurred_at timestamp without time zone,
    player_uid text,
    actor_uid text,
    payload jsonb
  )
  where x.event_key is not null
    and x.event_type is not null
  on conflict (event_key) do nothing;

  get diagnostics v_inserted = row_count;

  insert into public.dayz_file_cursors (file_path, byte_offset, updated_at)
  select x.file_path, x.byte_offset, now()
  from jsonb_to_recordset(coalesce(p_cursors, '[]'::jsonb)) as x(
    file_path text,
    byte_offset bigint
  )
  where x.file_path is not null and x.byte_offset >= 0
  on conflict (file_path) do update
    set byte_offset = excluded.byte_offset,
        updated_at = now();

  get diagnostics v_cursor_count = row_count;

  return jsonb_build_object('inserted_events', v_inserted, 'updated_cursors', v_cursor_count);
end;
$$;

revoke all on function public.dayz_ingest_batch(jsonb, jsonb) from public, anon, authenticated;
grant execute on function public.dayz_ingest_batch(jsonb, jsonb) to service_role;

revoke all on function public.dayz_confirm_link(text, text) from public, anon, authenticated;
grant execute on function public.dayz_confirm_link(text, text) to service_role;
