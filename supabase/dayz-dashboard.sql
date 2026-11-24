-- Atlanta DayZ: panel privado de estadísticas, logros y vinculación.
-- Ejecutar UNA SOLA VEZ en Supabase > SQL Editor, después de dayz-integration.sql.
-- No modifica las tablas de perfiles ni expone eventos de otros jugadores.

insert into public.dayz_achievement_definitions
  (achievement_key, name, description, rule, active)
values
  ('first_connection', 'Primer ingreso', 'Conectate al servidor por primera vez.', '{"event_type":"connected","uid_field":"player_uid","target":1}'::jsonb, true),
  ('regular_survivor', 'Superviviente habitual', 'Registrá 10 conexiones al servidor.', '{"event_type":"connected","uid_field":"player_uid","target":10}'::jsonb, true),
  ('first_kill', 'Primer enfrentamiento', 'Conseguí tu primera baja PvP.', '{"event_type":"pvp_kill","uid_field":"actor_uid","target":1}'::jsonb, true),
  ('hunter', 'Cazador', 'Conseguí 10 bajas PvP.', '{"event_type":"pvp_kill","uid_field":"actor_uid","target":10}'::jsonb, true),
  ('builder', 'Constructor', 'Completá 10 construcciones.', '{"event_type":"construction_completed","uid_field":"player_uid","target":10}'::jsonb, true),
  ('expressive', 'A tu manera', 'Realizá 10 emotes.', '{"event_type":"emote","uid_field":"player_uid","target":10}'::jsonb, true)
on conflict (achievement_key) do update
set name = excluded.name,
    description = excluded.description,
    rule = excluded.rule,
    active = excluded.active;

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

  select jsonb_build_object(
    'connections', count(*) filter (where e.event_type = 'connected'),
    'kills', count(*) filter (where e.event_type = 'pvp_kill' and e.actor_uid = v_bi_uid),
    'deaths', count(*) filter (where e.event_type = 'pvp_kill' and e.player_uid = v_bi_uid),
    'constructions', count(*) filter (where e.event_type = 'construction_completed' and e.player_uid = v_bi_uid),
    'objects_placed', count(*) filter (where e.event_type = 'object_placed' and e.player_uid = v_bi_uid),
    'emotes', count(*) filter (where e.event_type = 'emote' and e.player_uid = v_bi_uid)
  )
  into v_stats
  from public.dayz_events e
  where e.player_uid = v_bi_uid or e.actor_uid = v_bi_uid;

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
      and (
        case when d.rule->>'uid_field' = 'actor_uid'
          then e.actor_uid else e.player_uid end
      ) = v_bi_uid
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
