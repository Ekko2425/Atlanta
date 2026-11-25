-- Atlanta DayZ: reacciones Me gusta para el historial de actualizaciones.
-- Ejecutar una sola vez en Supabase > SQL Editor.

create table if not exists public.update_likes (
  update_id text not null check (char_length(update_id) between 1 and 100),
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (update_id, user_id)
);

alter table public.update_likes enable row level security;

-- Los navegadores no pueden consultar las filas individuales; solo la función
-- segura devuelve totales y si el usuario actual ya reaccionó.
revoke all on table public.update_likes from anon, authenticated;
grant insert, delete on table public.update_likes to authenticated;

drop policy if exists "Users can add their own update likes" on public.update_likes;
create policy "Users can add their own update likes"
  on public.update_likes for insert
  to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can remove their own update likes" on public.update_likes;
create policy "Users can remove their own update likes"
  on public.update_likes for delete
  to authenticated
  using (auth.uid() = user_id);

create or replace function public.get_update_like_counts(p_update_ids text[])
returns table (
  update_id text,
  like_count bigint,
  liked_by_me boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    requested.update_id,
    (
      select count(*)::bigint
      from public.update_likes likes
      where likes.update_id = requested.update_id
    ) as like_count,
    exists (
      select 1
      from public.update_likes likes
      where likes.update_id = requested.update_id
        and likes.user_id = auth.uid()
    ) as liked_by_me
  from unnest(coalesce(p_update_ids, array[]::text[])) as requested(update_id);
$$;

revoke all on function public.get_update_like_counts(text[]) from public;
grant execute on function public.get_update_like_counts(text[]) to anon, authenticated;
