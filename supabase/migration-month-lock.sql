-- For projects that already ran schema.sql: adds the "lock after auto-schedule" feature.
create table if not exists month_locks (
  month text primary key check (month ~ '^\d{4}-\d{2}$'),
  locked_at timestamptz not null default now()
);
alter table month_locks enable row level security;
create policy secretary_all on month_locks for all to authenticated using (true) with check (true);
grant select, insert, update, delete on table month_locks to authenticated;

create or replace function is_month_locked(p_month text)
returns boolean language sql security definer set search_path = public as
$$ select exists (select 1 from month_locks where month = p_month) $$;
grant execute on function is_month_locked(text) to anon, authenticated;

create or replace function submit_reply(p_month text, p_name text, p_off int[], p_prefer int[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_month !~ '^\d{4}-\d{2}$' then raise exception 'bad month'; end if;
  if not exists (select 1 from doctors where name = p_name) then raise exception 'unknown doctor'; end if;
  if auth.uid() is null and exists (select 1 from month_locks where month = p_month) then
    raise exception 'month locked';
  end if;
  insert into replies (month, doctor_name, off_days, prefer_days, submitted_at)
  values (p_month, p_name, coalesce(p_off,'{}'), coalesce(p_prefer,'{}'), now())
  on conflict (month, doctor_name) do update
    set off_days = excluded.off_days, prefer_days = excluded.prefer_days, submitted_at = now();
end $$;
