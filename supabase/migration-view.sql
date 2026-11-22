-- Adds the doctors' read-only schedule / reply-status view. Requires migration-pin.sql first.
-- Read-only view for doctors (employee number required): schedule + who has replied.
-- Returns jsonb: {status, schedule, holidays, extra_workdays, replies:[{name,replied,off_count}], locked}
create or replace function get_public_view(p_month text, p_key text, p_name text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text; st jsonb; reps jsonb;
begin
  v := verify_pin(p_name, p_pin);
  if v <> 'ok' then return jsonb_build_object('status', v); end if;
  select data into st from app_state where id = 1;
  select coalesce(jsonb_agg(jsonb_build_object(
           'name', d.name,
           'replied', r.doctor_name is not null,
           'off_count', coalesce(cardinality(r.off_days), 0)) order by d.sort_order, d.name), '[]'::jsonb)
    into reps
    from doctors d left join replies r on r.doctor_name = d.name and r.month = p_month;
  return jsonb_build_object(
    'status', 'ok',
    'schedule', st->'schedule'->p_key,
    'holidays', st->'secretarySettings'->'holidays'->p_key,
    'extra_workdays', st->'secretarySettings'->'extraWorkdays'->p_key,
    'replies', reps,
    'locked', exists (select 1 from month_locks where month = p_month));
end $$;
grant execute on function get_public_view(text, text, text, text) to anon, authenticated;
