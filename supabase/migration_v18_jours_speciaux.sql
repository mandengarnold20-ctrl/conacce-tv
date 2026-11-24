-- Conacce TV — v18 : calendrier des jours spéciaux (étape 8).
-- Un jour spécial (Noël, Pâques, congrès…) = une plage horaire précise, un nom, et des rendez-vous
-- préparés à l'avance (souvent à partir d'un modèle de journée).
-- Si « remplacer la grille habituelle » est coché, les rendez-vous qui se répètent (chaque jour,
-- chaque semaine) ne passent pas pendant cette plage : seule la journée spéciale passe
-- (la playlist en boucle continue de combler les trous).

create table if not exists public.tv_special_days (
  id              uuid primary key default gen_random_uuid(),
  name            text not null check (char_length(name) between 1 and 60),
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  replace_regular boolean not null default true,
  template_id     uuid,
  created_at      timestamptz not null default now(),
  created_by      uuid default auth.uid(),
  constraint tv_special_days_range check (ends_at > starts_at and ends_at - starts_at <= interval '7 days')
);

-- Les rendez-vous d'un jour spécial portent son identifiant (effacés avec lui depuis la régie).
alter table public.tv_programs add column if not exists special_day_id uuid;
create index if not exists tv_programs_special_day on public.tv_programs (special_day_id) where special_day_id is not null;

alter table public.tv_special_days enable row level security;

-- Lecture : tout le monde (l'appli en a besoin pour calculer la grille, même hors connexion).
drop policy if exists tv_special_days_read on public.tv_special_days;
create policy tv_special_days_read on public.tv_special_days for select to anon, authenticated using (true);

drop policy if exists tv_special_days_insert on public.tv_special_days;
create policy tv_special_days_insert on public.tv_special_days
  for insert to authenticated with check (public.can_program());

drop policy if exists tv_special_days_update on public.tv_special_days;
create policy tv_special_days_update on public.tv_special_days
  for update to authenticated using (public.can_program()) with check (public.can_program());

drop policy if exists tv_special_days_delete on public.tv_special_days;
create policy tv_special_days_delete on public.tv_special_days
  for delete to authenticated using (public.can_program());

grant select on public.tv_special_days to anon, authenticated;
grant insert, update, delete on public.tv_special_days to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.tv_special_days;
exception when duplicate_object then null; end $$;

select 'jours speciaux' as etape, 'ok' as resultat;
