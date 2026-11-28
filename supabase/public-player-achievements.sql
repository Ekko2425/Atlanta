-- Atlanta DayZ: logros desbloqueados visibles en perfiles públicos.
-- Ejecutar nuevamente en Supabase > SQL Editor para actualizar la función.
-- Solo devuelve nombre, descripción y clave de logros completados; nunca expone BI UID ni eventos.
-- Usa la misma normalización de BI UID que get_my_dayz_dashboard().

create or replace function public.get_public_player_achievements(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_bi_uid text;
  v_normalized_uid text;
  v_achievements jsonb;
begin
  if p_user_id is null then
    raise exception 'Perfil no válido.';
  end if;

  select l.bi_uid into v_bi_uid
  from public.dayz_player_links l
  where l.user_id = p_user_id;

  if v_bi_uid is null then
    return jsonb_build_object('linked', false, 'achievements', '[]'::jsonb);
  end if;

  -- Igual que la función del panel personal: elimina los marcadores
  -- "id=" y "_c=" antes de comparar los identificadores.
  v_normalized_uid := regexp_replace(
    regexp_replace(v_bi_uid, '^id=', ''),
    '_c=$',
    ''
  );

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'achievement_key', d.achievement_key,
        'name', d.name,
        'description', d.description
      )
      order by d.achievement_key
    ),
    '[]'::jsonb
  )
  into v_achievements
  from public.dayz_achievement_definitions d
  cross join lateral (
    select count(*)::bigint as current_progress
    from public.dayz_events e
    where e.event_type = d.rule->>'event_type'
      and regexp_replace(
        regexp_replace(
          case when d.rule->>'uid_field' = 'actor_uid'
            then e.actor_uid else e.player_uid end,
          '^id=', ''
        ),
        '_c=$',
        ''
      ) = v_normalized_uid
  ) p
  where d.active = true
    and p.current_progress >= (d.rule->>'target')::bigint;

  return jsonb_build_object('linked', true, 'achievements', v_achievements);
end;
$$;

revoke all on function public.get_public_player_achievements(uuid) from public;
grant execute on function public.get_public_player_achievements(uuid) to anon, authenticated;
