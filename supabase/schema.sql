-- Run once in Supabase: SQL Editor -> New query -> paste -> Run.

create table if not exists doctors (
  name text primary key,
  sort_order int not null default 0
);
insert into doctors (name, sort_order) values
  ('江毅彥',0),('張書豪',1),('徐得愷',2),('陳勇璋',3),('王俊量',4),
  ('羅文鴻',5),('洪嘉鴻',6),('葉炳君',7),('李元甫',8),('李宗霖',9)
on conflict (name) do nothing;

create table if not exists replies (
  month text not null check (month ~ '^\d{4}-\d{2}$'),
  doctor_name text not null references doctors(name) on update cascade on delete cascade,
  off_days int[] not null default '{}',
  prefer_days int[] not null default '{}',
  submitted_at timestamptz not null default now(),
  primary key (month, doctor_name)
);

-- Secretary's schedule / staff / settings (single row)
create table if not exists app_state (
  id int primary key default 1 check (id = 1),
  data jsonb not null,
  updated_at timestamptz not null default now()
);

-- Months whose reply form is locked (set automatically after 自動排班)
create table if not exists month_locks (
  month text primary key check (month ~ '^\d{4}-\d{2}$'),
  locked_at timestamptz not null default now()
);

-- Per-doctor PIN = employee number (exactly 5 digits)
-- (set by the secretary, never readable by anonymous users)
create table if not exists doctor_pins (
  name text primary key references doctors(name) on update cascade on delete cascade,
  pin text not null check (pin ~ '^\d{5}$')
);
-- Failed-attempt counter: 5 wrong PINs lock that doctor out for 15 minutes
create table if not exists pin_attempts (
  name text primary key references doctors(name) on update cascade on delete cascade,
  failed int not null default 0,
  locked_until timestamptz
);
alter table doctor_pins  enable row level security;
alter table pin_attempts enable row level security;
drop policy if exists secretary_all on doctor_pins;
create policy secretary_all on doctor_pins for all to authenticated using (true) with check (true);
-- pin_attempts has no policy on purpose: only the security-definer functions below touch it.
grant select, insert, update, delete on table doctor_pins to authenticated;

alter table month_locks enable row level security;
alter table doctors   enable row level security;
alter table replies   enable row level security;
alter table app_state enable row level security;

-- Only signed-in users (the secretary) can touch tables directly.
-- Turn OFF "Allow new users to sign up" so nobody else can become one.
drop policy if exists secretary_all on doctors;
create policy secretary_all on doctors   for all to authenticated using (true) with check (true);
drop policy if exists secretary_all on replies;
create policy secretary_all on replies   for all to authenticated using (true) with check (true);
drop policy if exists secretary_all on month_locks;
create policy secretary_all on month_locks for all to authenticated using (true) with check (true);
drop policy if exists secretary_all on app_state;
create policy secretary_all on app_state for all to authenticated using (true) with check (true);

-- Newer Supabase projects do not expose new tables to the API automatically.
-- Grant table privileges to signed-in users only (never to anon).
grant usage on schema public to authenticated;
grant select, insert, update, delete on table doctors, replies, app_state, month_locks to authenticated;

-- Doctors are anonymous: they only get these narrow functions.
create or replace function list_doctors()
returns table(name text) language sql security definer set search_path = public as
$$ select name from doctors order by sort_order, name $$;

create or replace function is_month_locked(p_month text)
returns boolean language sql security definer set search_path = public as
$$ select exists (select 1 from month_locks where month = p_month) $$;

-- Internal: checks a doctor's PIN. Returns 'ok' | 'bad_pin' | 'locked_out' | 'no_pin'.
-- Returns a status (instead of raising) so the failed-attempt counter is committed.
create or replace function verify_pin(p_name text, p_pin text)
returns text language plpgsql security definer set search_path = public as $$
declare v_pin text; v_locked timestamptz;
begin
  select pin into v_pin from doctor_pins where name = p_name;
  if v_pin is null then return 'no_pin'; end if;
  select locked_until into v_locked from pin_attempts where name = p_name;
  if v_locked is not null and v_locked > now() then return 'locked_out'; end if;
  if p_pin is not null and lower(p_pin) = lower(v_pin) then
    delete from pin_attempts where name = p_name;
    return 'ok';
  end if;
  update pin_attempts
     set failed = case when locked_until is not null and locked_until <= now() then 1 else failed + 1 end
   where name = p_name;
  if not found then insert into pin_attempts (name, failed) values (p_name, 1); end if;
  update pin_attempts set locked_until = now() + interval '15 minutes' where name = p_name and failed >= 5;
  return 'bad_pin';
end $$;
revoke execute on function verify_pin(text, text) from public, anon, authenticated;

-- Doctor reads their own reply (PIN required). Returns jsonb {status, off_days, prefer_days}.
create or replace function get_reply(p_month text, p_name text, p_pin text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text; r replies%rowtype;
begin
  v := verify_pin(p_name, p_pin);
  if v <> 'ok' then return jsonb_build_object('status', v); end if;
  select * into r from replies where month = p_month and doctor_name = p_name;
  if not found then return jsonb_build_object('status', 'ok', 'off_days', '[]'::jsonb, 'prefer_days', '[]'::jsonb); end if;
  return jsonb_build_object('status', 'ok', 'off_days', to_jsonb(r.off_days), 'prefer_days', to_jsonb(r.prefer_days));
end $$;

-- Doctor submits (PIN required) / secretary edits (signed in, no PIN needed).
-- Returns 'ok' | 'bad_pin' | 'locked_out' | 'no_pin' | 'month_locked'.
create or replace function submit_reply(p_month text, p_name text, p_off int[], p_prefer int[], p_pin text default null)
returns text language plpgsql security definer set search_path = public as $$
declare v text;
begin
  if p_month !~ '^\d{4}-\d{2}$' then raise exception 'bad month'; end if;
  if not exists (select 1 from doctors where name = p_name) then raise exception 'unknown doctor'; end if;
  if auth.uid() is null then
    v := verify_pin(p_name, p_pin);
    if v <> 'ok' then return v; end if;
    if exists (select 1 from month_locks where month = p_month) then return 'month_locked'; end if;
  end if;
  insert into replies (month, doctor_name, off_days, prefer_days, submitted_at)
  values (p_month, p_name, coalesce(p_off,'{}'), coalesce(p_prefer,'{}'), now())
  on conflict (month, doctor_name) do update
    set off_days = excluded.off_days, prefer_days = excluded.prefer_days, submitted_at = now();
  return 'ok';
end $$;

grant execute on function get_reply(text,text,text) to anon, authenticated;
grant execute on function submit_reply(text,text,int[],int[],text) to anon, authenticated;

grant execute on function list_doctors()  to anon, authenticated;
grant execute on function is_month_locked(text) to anon, authenticated;

-- Live updates for the secretary's screen
alter publication supabase_realtime add table replies;
