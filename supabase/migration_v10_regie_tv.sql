-- Conacce TV — v10 : régie TV (lecture / pause / arrêt de la chaîne, plan de la semaine).

alter table public.tv_programs add column if not exists repeat_weekly boolean not null default false;

-- État de la chaîne : une seule ligne, lue par tous, modifiée par la régie.
-- anchor : départ de la playlist en boucle (Play après Stop = la playlist repart du n° 1).
-- paused_at : heure de la mise en pause (à la reprise, la playlist repart là où elle s'était arrêtée).
create table if not exists public.tv_channel (
  id          integer primary key default 1 check (id = 1),
  status      text not null default 'playing' check (status in ('playing', 'paused', 'stopped')),
  anchor      timestamptz not null default '2026-01-01T00:00:00Z',
  paused_at   timestamptz,
  updated_at  timestamptz not null default now()
);
insert into public.tv_channel (id) values (1) on conflict (id) do nothing;

alter table public.tv_channel enable row level security;
drop policy if exists "chaine tv : lecture" on public.tv_channel;
create policy "chaine tv : lecture" on public.tv_channel for select to anon, authenticated using (true);
grant select on public.tv_channel to anon, authenticated;

-- Commandes de la régie, calculées à l'heure du serveur : play, pause, stop, clear (tout supprimer).
create or replace function public.tv_control(action text)
returns public.tv_channel language plpgsql security definer set search_path = public as $$
declare c public.tv_channel;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  select * into c from public.tv_channel where id = 1 for update;
  if action = 'play' then
    if c.status = 'paused' and c.paused_at is not null then
      update public.tv_channel set status = 'playing', anchor = anchor + (now() - paused_at), paused_at = null, updated_at = now() where id = 1;
    elsif c.status = 'stopped' then
      update public.tv_channel set status = 'playing', anchor = now(), paused_at = null, updated_at = now() where id = 1;
    end if;
  elsif action = 'pause' then
    if c.status = 'playing' then
      update public.tv_channel set status = 'paused', paused_at = now(), updated_at = now() where id = 1;
    end if;
  elsif action = 'stop' then
    update public.tv_channel set status = 'stopped', paused_at = null, updated_at = now() where id = 1;
  elsif action = 'restart' then
    update public.tv_channel set anchor = now(), updated_at = now() where id = 1;
  elsif action = 'clear' then
    delete from public.tv_programs where true;
    update public.tv_channel set status = 'playing', paused_at = null, anchor = now(), updated_at = now() where id = 1;
  else
    raise exception 'Commande inconnue : %', action;
  end if;
  select * into c from public.tv_channel where id = 1;
  return c;
end $$;
revoke all on function public.tv_control(text) from public, anon;
grant execute on function public.tv_control(text) to authenticated;
grant execute on function public.is_admin() to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.tv_channel;
exception when duplicate_object then null; end $$;

select 'ok' as regie_tv;
