-- Atlanta DayZ: perfiles públicos de la comunidad.
-- Ejecutar una sola vez en Supabase > SQL Editor.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique
    check (char_length(username) between 3 and 20)
    check (username ~ '^[A-Za-z0-9_]+$'),
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Los miembros autenticados pueden consultar perfiles de la comunidad.
drop policy if exists "Community members can view profiles" on public.profiles;
create policy "Community members can view profiles"
  on public.profiles for select
  to authenticated
  using (true);

-- Cada usuario solo puede crear/editar su propio perfil.
drop policy if exists "Users can insert their own profile" on public.profiles;
create policy "Users can insert their own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

drop policy if exists "Users can update their own profile" on public.profiles;
create policy "Users can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- Crea automáticamente el perfil al registrarse. Si el nombre ya existe,
-- agrega un sufijo numérico para que el registro no falle.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  base_name text;
  candidate text;
  suffix integer := 0;
begin
  base_name := coalesce(new.raw_user_meta_data ->> 'username', 'Jugador');
  base_name := regexp_replace(base_name, '[^A-Za-z0-9_]', '', 'g');
  base_name := left(base_name, 20);
  if char_length(base_name) < 3 then
    base_name := 'Player' || left(replace(new.id::text, '-', ''), 8);
  end if;

  candidate := base_name;
  while exists (select 1 from public.profiles p where lower(p.username) = lower(candidate)) loop
    suffix := suffix + 1;
    candidate := left(base_name, 20 - char_length(suffix::text)) || suffix::text;
  end loop;

  insert into public.profiles (id, username)
  values (new.id, candidate);
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- La función se ejecuta como definidor para que el alta de Auth pueda crear
-- el perfil sin conceder permisos elevados al navegador.
revoke all on function public.handle_new_user() from public, anon, authenticated;
