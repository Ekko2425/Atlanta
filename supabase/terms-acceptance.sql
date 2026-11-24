-- Atlanta DayZ: aceptación obligatoria de Términos y Condiciones.
-- Ejecutar UNA VEZ en Supabase > SQL Editor > New query.
-- Versión vigente al momento de esta migración: 2026-11-24.

create table if not exists public.legal_acceptances (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  document_type text not null check (document_type = 'terms'),
  document_version text not null,
  accepted_at timestamptz not null default now(),
  unique (user_id, document_type, document_version)
);

alter table public.legal_acceptances enable row level security;

-- Ningún usuario puede leer o modificar estos registros desde el navegador.
revoke all on table public.legal_acceptances from public, anon, authenticated;

-- Bloquea el alta de cuentas si no se envía la aceptación de la versión vigente.
create or replace function public.validate_atlanta_terms_acceptance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'terms_accepted', 'false') <> 'true'
     or coalesce(new.raw_user_meta_data ->> 'terms_version', '') <> '2026-11-24' then
    raise exception 'Debés aceptar los Términos y Condiciones vigentes de Atlanta DayZ para crear una cuenta.';
  end if;
  return new;
end;
$$;

-- Guarda la constancia con fecha/hora del servidor, no del navegador.
create or replace function public.record_atlanta_terms_acceptance()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.legal_acceptances
    (user_id, document_type, document_version, accepted_at)
  values
    (new.id, 'terms', '2026-11-24', now())
  on conflict (user_id, document_type, document_version) do nothing;
  return new;
end;
$$;

drop trigger if exists require_atlanta_terms_before_signup on auth.users;
create trigger require_atlanta_terms_before_signup
  before insert on auth.users
  for each row execute procedure public.validate_atlanta_terms_acceptance();

drop trigger if exists record_atlanta_terms_after_signup on auth.users;
create trigger record_atlanta_terms_after_signup
  after insert on auth.users
  for each row execute procedure public.record_atlanta_terms_acceptance();

revoke all on function public.validate_atlanta_terms_acceptance() from public, anon, authenticated;
revoke all on function public.record_atlanta_terms_acceptance() from public, anon, authenticated;
