-- Lets doctors' fill pages know the secretary's extra holidays (e.g. 12/25).
-- Public (no PIN): this month's extra holidays and make-up workdays, so doctors' fill pages count them too.
create or replace function get_month_holidays(p_key text)
returns jsonb language sql security definer set search_path = public as
$$ select jsonb_build_object(
     'holidays', coalesce(data->'secretarySettings'->'holidays'->p_key, '[]'::jsonb),
     'extra_workdays', coalesce(data->'secretarySettings'->'extraWorkdays'->p_key, '[]'::jsonb))
   from app_state where id = 1 $$;
grant execute on function get_month_holidays(text) to anon, authenticated;
