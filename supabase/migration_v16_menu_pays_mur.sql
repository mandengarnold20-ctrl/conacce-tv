-- =============================================================================
--  CONACCE TV — Nouveau menu (v16)
--  * CCA et CIU : vidéos et photos rangées par pays (code ISO, ex. « BJ »).
--    Sans pays : « International ».
--  * Mur de commentaires général (page « Commentaires » de l'appli).
-- =============================================================================

alter table public.sermons add column if not exists country text;
alter table public.sermons drop constraint if exists sermons_country_check;
alter table public.sermons add constraint sermons_country_check check (country is null or country ~ '^[A-Z]{2}$');

alter table public.gallery_photos add column if not exists country text;
alter table public.gallery_photos drop constraint if exists gallery_photos_country_check;
alter table public.gallery_photos add constraint gallery_photos_country_check check (country is null or country ~ '^[A-Z]{2}$');

-- Choix de la régie : afficher (ou non) la barre des pays dans CCA et dans CIU.
alter table public.app_settings add column if not exists show_countries_cca boolean not null default true;
alter table public.app_settings add column if not exists show_countries_ciu boolean not null default true;

-- ─── Mur de commentaires ───
create table if not exists public.wall_comments (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(btrim(name)) between 1 and 40),
  country_code  text check (country_code is null or country_code ~ '^[A-Z]{2}$'),
  body          text not null check (char_length(btrim(body)) between 1 and 1000),
  visitor_id    uuid,
  is_hidden     boolean not null default false,
  created_at    timestamptz not null default now()
);
create index if not exists wall_comments_created_idx on public.wall_comments (created_at desc);

alter table public.wall_comments enable row level security;

drop policy if exists "mur : lecture" on public.wall_comments;
create policy "mur : lecture" on public.wall_comments for select to anon, authenticated
  using (not is_hidden or public.is_admin());

drop policy if exists "mur : écrire" on public.wall_comments;
create policy "mur : écrire" on public.wall_comments for insert to anon, authenticated
  with check (not is_hidden);

drop policy if exists "mur : admin modère" on public.wall_comments;
create policy "mur : admin modère" on public.wall_comments for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "mur : admin supprime" on public.wall_comments;
create policy "mur : admin supprime" on public.wall_comments for delete to authenticated
  using (public.is_admin());

-- Anti-spam : un message toutes les 10 secondes par appareil.
create or replace function public.wall_comments_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  new.is_hidden := false;
  if new.visitor_id is not null and exists (
    select 1 from wall_comments where visitor_id = new.visitor_id and created_at > now() - interval '10 seconds'
  ) then
    raise exception 'Patientez quelques secondes avant un nouveau message.';
  end if;
  return new;
end $$;
drop trigger if exists wall_comments_guard on public.wall_comments;
create trigger wall_comments_guard before insert on public.wall_comments
  for each row execute function public.wall_comments_guard();

grant select, insert on public.wall_comments to anon, authenticated;
grant update, delete on public.wall_comments to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.wall_comments;
exception when duplicate_object then null; end $$;

select 'Nouveau menu : pays et mur de commentaires prêts' as resultat;
