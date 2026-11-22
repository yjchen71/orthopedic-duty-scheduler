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

alter table doctors   enable row level security;
alter table replies   enable row level security;
alter table app_state enable row level security;

-- Only signed-in users (the secretary) can touch tables directly.
-- Turn OFF "Allow new users to sign up" so nobody else can become one.
create policy secretary_all on doctors   for all to authenticated using (true) with check (true);
create policy secretary_all on replies   for all to authenticated using (true) with check (true);
create policy secretary_all on app_state for all to authenticated using (true) with check (true);

-- Newer Supabase projects do not expose new tables to the API automatically.
-- Grant table privileges to signed-in users only (never to anon).
grant usage on schema public to authenticated;
grant select, insert, update, delete on table doctors, replies, app_state to authenticated;

-- Doctors are anonymous: they only get these narrow functions.
create or replace function list_doctors()
returns table(name text) language sql security definer set search_path = public as
$$ select name from doctors order by sort_order, name $$;

create or replace function get_reply(p_month text, p_name text)
returns table(off_days int[], prefer_days int[]) language sql security definer set search_path = public as
$$ select off_days, prefer_days from replies where month = p_month and doctor_name = p_name $$;

create or replace function submit_reply(p_month text, p_name text, p_off int[], p_prefer int[])
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_month !~ '^\d{4}-\d{2}$' then raise exception 'bad month'; end if;
  if not exists (select 1 from doctors where name = p_name) then raise exception 'unknown doctor'; end if;
  insert into replies (month, doctor_name, off_days, prefer_days, submitted_at)
  values (p_month, p_name, coalesce(p_off,'{}'), coalesce(p_prefer,'{}'), now())
  on conflict (month, doctor_name) do update
    set off_days = excluded.off_days, prefer_days = excluded.prefer_days, submitted_at = now();
end $$;

grant execute on function list_doctors()  to anon, authenticated;
grant execute on function get_reply(text,text) to anon, authenticated;
grant execute on function submit_reply(text,text,int[],int[]) to anon, authenticated;

-- Live updates for the secretary's screen
alter publication supabase_realtime add table replies;
