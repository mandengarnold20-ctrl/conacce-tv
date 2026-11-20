-- Conacce TV — v9 : programmation de la chaîne 24 h/24.
-- Chaque programme est un lien YouTube ou une vidéo Cloudflare Stream, avec sa durée.
-- « Boucle » : les programmes sans heure passent l'un après l'autre, sans fin.
-- « Rendez-vous » : un programme avec une heure de début passe à cette heure-là (et chaque jour si coché).

create table if not exists public.tv_programs (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  source        text not null default 'youtube' check (source in ('youtube', 'file')),
  video_url     text not null,
  duration      integer not null check (duration > 0),
  position      integer not null default 0,
  start_at      timestamptz,
  repeat_daily  boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now()
);

alter table public.tv_programs enable row level security;

drop policy if exists "programmes tv : lecture" on public.tv_programs;
create policy "programmes tv : lecture" on public.tv_programs for select to anon, authenticated
  using (is_active or public.is_admin());

drop policy if exists "programmes tv : admin écrit" on public.tv_programs;
create policy "programmes tv : admin écrit" on public.tv_programs for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

grant select on public.tv_programs to anon, authenticated;
grant insert, update, delete on public.tv_programs to authenticated;

-- Heure du serveur : tout le monde, partout dans le monde, voit la même image au même moment.
create or replace function public.tv_now() returns timestamptz
  language sql stable as $$ select now() $$;
grant execute on function public.tv_now() to anon, authenticated;

do $$ begin
  alter publication supabase_realtime add table public.tv_programs;
exception when duplicate_object then null; end $$;

select 'ok' as programmation_tv;
