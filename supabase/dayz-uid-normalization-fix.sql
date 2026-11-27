-- Atlanta DayZ: corregir comparación de BI UID entre eventos y vinculaciones.
-- Conserva todos los eventos y vínculos existentes; no borra ni reescribe datos.
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor.

create or replace function public.get_my_dayz_dashboard()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_bi_uid text;
  v_normalized_uid text;
  v_stats jsonb;
  v_achievements jsonb;
begin
  if v_user_id is null then
    raise exception 'Debés iniciar sesión.';
  end if;

  select l.bi_uid into v_bi_uid
  from public.dayz_player_links l
  where l.user_id = v_user_id;

  if v_bi_uid is null then
    return jsonb_build_object(
      'linked', false,
      'stats', jsonb_build_object(
        'connections', 0, 'kills', 0, 'deaths', 0,
        'constructions', 0, 'objects_placed', 0, 'emotes', 0
      ),
      'achievements', '[]'::jsonb
    );
  end if;

  -- En el log de eventos puede venir "id=" delante del BI UID,
  -- mientras que el mensaje de vinculación puede añadir "_c=" al final.
  -- Se quitan únicamente esos marcadores de formato para comparar el mismo UID.
  v_normalized_uid := regexp_replace(
    regexp_replace(v_bi_uid, '^id=', ''),
    '_c=$',
    ''
  );

  select jsonb_build_object(
    'connections', count(*) filter (
      where e.event_type = 'connected'
        and regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    ),
    'kills', count(*) filter (
      where e.event_type = 'pvp_kill'
        and regexp_replace(regexp_replace(e.actor_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    ),
    'deaths', count(*) filter (
      where e.event_type = 'pvp_kill'
        and regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    ),
    'constructions', count(*) filter (
      where e.event_type = 'construction_completed'
        and regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    ),
    'objects_placed', count(*) filter (
      where e.event_type = 'object_placed'
        and regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    ),
    'emotes', count(*) filter (
      where e.event_type = 'emote'
        and regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    )
  )
  into v_stats
  from public.dayz_events e
  where
    regexp_replace(regexp_replace(e.player_uid, '^id=', ''), '_c=$', '') = v_normalized_uid
    or regexp_replace(regexp_replace(e.actor_uid, '^id=', ''), '_c=$', '') = v_normalized_uid;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'achievement_key', d.achievement_key,
        'name', d.name,
        'description', d.description,
        'progress', least(p.current_progress, (d.rule->>'target')::bigint),
        'target', (d.rule->>'target')::bigint,
        'unlocked', p.current_progress >= (d.rule->>'target')::bigint
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
  where d.active = true;

  return jsonb_build_object(
    'linked', true,
    'stats', coalesce(v_stats, '{}'::jsonb),
    'achievements', v_achievements
  );
end;
$$;

revoke all on function public.get_my_dayz_dashboard() from public, anon;
grant execute on function public.get_my_dayz_dashboard() to authenticated;
