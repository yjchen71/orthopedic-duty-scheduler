-- Use 5-digit employee numbers as the doctor PIN.
-- Safe to run whether or not migration-pin.sql was already applied.
alter table doctor_pins drop constraint if exists doctor_pins_pin_check;
alter table doctor_pins add constraint doctor_pins_pin_check check (pin ~ '^\d{5}$');

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
