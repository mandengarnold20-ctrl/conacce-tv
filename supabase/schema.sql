-- =============================================================================
--  CONACCE TV — Schéma Supabase complet
--  À exécuter en une fois dans : Supabase > SQL Editor > New query > Run
--
--   1. Types et fonctions utilitaires
--   2. Comptes (app_users) + rôle administrateur
--   3. Contenu : direct TV, Radio Dunamis FM, cultes, Œuvres d'Or, affiches, réglages
--   4. Sécurité (lecture publique, écriture réservée aux administrateurs)
--   5. Statistiques (visiteurs, vues, auditeurs) + tableau de bord
--   6. Stockage des fichiers (images, médias)
--   7. Temps réel (badge EN DIRECT instantané) + données de départ
-- =============================================================================

create extension if not exists pg_trgm;

-- ─── 1. TYPES ET FONCTIONS ───────────────────────────────────────────────────
do $$ begin create type public.app_role as enum ('user', 'admin');
exception when duplicate_object then null; end $$;

do $$ begin create type public.sermon_category as enum ('dimanche', 'enseignement', 'priere', 'special', 'autre');
exception when duplicate_object then null; end $$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end $$;

-- ─── 2. COMPTES ──────────────────────────────────────────────────────────────
create table if not exists public.app_users (
  id            uuid primary key references auth.users (id) on delete cascade,
  display_name  text,
  role          public.app_role not null default 'user',
  created_at    timestamptz     not null default now()
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from app_users where id = auth.uid() and role = 'admin');
$$;

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.app_users (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ─── 3. CONTENU ──────────────────────────────────────────────────────────────

-- 3.1 Conacce TV en direct (une seule ligne)
create table if not exists public.live_stream (
  id                 uuid primary key default gen_random_uuid(),
  title              text        not null default 'Conacce TV',
  hls_url            text,                         -- lien .m3u8 (Cloudflare Stream)
  is_live            boolean     not null default false,
  speaker            text,                         -- bandeau : nom de l'orateur
  message_title      text,                         -- bandeau : titre du message
  next_live_info     text,                         -- « Prochain culte : dimanche 9h »
  next_live_at       timestamptz,
  offline_image_url  text,
  updated_at         timestamptz not null default now(),
  constraint live_requires_url check (not is_live or hls_url is not null)
);
create unique index if not exists live_stream_singleton on public.live_stream ((true));

-- 3.2 Radio Dunamis FM (une seule ligne)
create table if not exists public.radio (
  id            uuid primary key default gen_random_uuid(),
  name          text        not null default 'Radio Dunamis FM',
  stream_url    text,                              -- flux audio (mp3, aac ou .m3u8)
  is_on_air     boolean     not null default false,
  current_show  text,                              -- émission en cours
  host          text,                              -- animateur
  cover_url     text,
  updated_at    timestamptz not null default now(),
  constraint radio_requires_url check (not is_on_air or stream_url is not null)
);
create unique index if not exists radio_singleton on public.radio ((true));

-- 3.3 Cultes enregistrés (publiés par l'église, comme sur YouTube)
create table if not exists public.sermons (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  description      text,
  category         public.sermon_category not null default 'dimanche',
  speaker          text,
  preached_on      date,
  video_url        text,                           -- .m3u8 Cloudflare Stream ou .mp4
  audio_url        text,                           -- .mp3 (écoute hors connexion)
  thumbnail_url    text,
  duration         integer,                        -- secondes
  is_featured      boolean not null default false,
  is_downloadable  boolean not null default true,
  is_published     boolean not null default true,
  view_count       integer not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint sermon_has_source check (video_url is not null or audio_url is not null)
);
create index if not exists sermons_recent_idx on public.sermons (is_published, preached_on desc, created_at desc);
create index if not exists sermons_title_trgm on public.sermons using gin (title gin_trgm_ops);

-- 3.4 Œuvres d'Or (livres de l'homme de Dieu)
create table if not exists public.works (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  subtitle     text,
  description  text,
  cover_url    text,
  pdf_url      text,                               -- lecture dans l'appli
  pages        integer,
  year         integer,
  is_free      boolean not null default true,
  price_label  text,                               -- ex : « 5 000 FCFA »
  buy_url      text,                               -- achat sur un site externe
  is_featured  boolean not null default false,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- 3.5 Affiches de l'accueil
create table if not exists public.home_banners (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  subtitle     text,
  image_url    text not null,
  cta_label    text,
  target_type  text not null default 'none' check (target_type in ('none', 'live', 'radio', 'sermon', 'work', 'url')),
  target_id    uuid,
  target_url   text,
  is_active    boolean not null default true,
  sort_order   integer not null default 0,
  starts_at    timestamptz,
  ends_at      timestamptz,
  created_at   timestamptz not null default now()
);

-- 3.6 Réglages de l'appli (une seule ligne, id = 1)
create table if not exists public.app_settings (
  id               integer primary key default 1 check (id = 1),
  man_of_god_name  text,                           -- nom affiché dans Œuvres d'Or
  donation_url     text,                           -- don : ouvert dans le navigateur
  whatsapp_url     text,
  facebook_url     text,
  youtube_url      text,
  contact_email    text,
  updated_at       timestamptz not null default now()
);

do $$ declare t text; begin
  foreach t in array array['live_stream','radio','sermons','works','app_settings'] loop
    execute format('drop trigger if exists %I_updated on public.%I', t, t);
    execute format('create trigger %I_updated before update on public.%I for each row execute function public.set_updated_at()', t, t);
  end loop;
end $$;

-- ─── 4. SÉCURITÉ ─────────────────────────────────────────────────────────────
alter table public.app_users     enable row level security;
alter table public.live_stream   enable row level security;
alter table public.radio         enable row level security;
alter table public.sermons       enable row level security;
alter table public.works         enable row level security;
alter table public.home_banners  enable row level security;
alter table public.app_settings  enable row level security;

drop policy if exists "compte : lire le sien" on public.app_users;
create policy "compte : lire le sien" on public.app_users for select to authenticated
  using (id = auth.uid() or public.is_admin());
drop policy if exists "compte : admin gère" on public.app_users;
create policy "compte : admin gère" on public.app_users for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

do $$ declare t text; begin
  foreach t in array array['live_stream','radio','works','home_banners','app_settings'] loop
    execute format('drop policy if exists "lecture publique" on public.%I', t);
    execute format('create policy "lecture publique" on public.%I for select to anon, authenticated using (true)', t);
    execute format('drop policy if exists "admin écrit" on public.%I', t);
    execute format('create policy "admin écrit" on public.%I for all to authenticated using (public.is_admin()) with check (public.is_admin())', t);
  end loop;
end $$;

-- Les cultes non publiés ne sont visibles que par les administrateurs
drop policy if exists "lecture publique" on public.sermons;
create policy "lecture publique" on public.sermons for select to anon, authenticated
  using (is_published or public.is_admin());
drop policy if exists "admin écrit" on public.sermons;
create policy "admin écrit" on public.sermons for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ─── 5. STATISTIQUES ─────────────────────────────────────────────────────────
create table if not exists public.analytics_events (
  id          bigint generated always as identity primary key,
  kind        text   not null check (kind in ('visit', 'play', 'live', 'radio', 'read')),
  visitor_id  uuid   not null,
  item_id     uuid,                                -- culte vu ou œuvre lue
  platform    text,
  day         date   not null default (now() at time zone 'utc')::date,
  created_at  timestamptz not null default now()
);
create unique index if not exists analytics_unique_per_day on public.analytics_events
  (kind, visitor_id, day, coalesce(item_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists analytics_day_idx on public.analytics_events (day, kind);
alter table public.analytics_events enable row level security;   -- aucun accès direct

create or replace function public.track(p_kind text, p_visitor uuid, p_item uuid default null, p_platform text default null)
returns void language plpgsql security definer set search_path = public as $$
declare inserted int;
begin
  if p_kind not in ('visit', 'play', 'live', 'radio', 'read') or p_visitor is null then return; end if;
  insert into analytics_events (kind, visitor_id, item_id, platform)
  values (p_kind, p_visitor, case when p_kind in ('play', 'read') then p_item end,
          case when p_platform in ('android', 'ios', 'web', 'desktop', 'tv') then p_platform else 'autre' end)
  on conflict do nothing;
  get diagnostics inserted = row_count;
  if inserted > 0 and p_kind = 'play' and p_item is not null then
    update sermons set view_count = view_count + 1 where id = p_item;
  end if;
end $$;
grant execute on function public.track(text, uuid, uuid, text) to anon, authenticated;

create or replace function public.admin_stats(p_days integer default 30)
returns json language plpgsql stable security definer set search_path = public as $$
declare since date := (now() at time zone 'utc')::date - greatest(p_days, 1) + 1;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  return json_build_object(
    'visiteurs_uniques',    (select count(distinct visitor_id) from analytics_events where kind = 'visit' and day >= since),
    'visiteurs_aujourdhui', (select count(*) from analytics_events where kind = 'visit' and day = (now() at time zone 'utc')::date),
    'vues_cultes',          (select count(*) from analytics_events where kind = 'play' and day >= since),
    'spectateurs_tv',       (select count(distinct visitor_id) from analytics_events where kind = 'live' and day >= since),
    'auditeurs_radio',      (select count(distinct visitor_id) from analytics_events where kind = 'radio' and day >= since),
    'lectures_oeuvres',     (select count(*) from analytics_events where kind = 'read' and day >= since),
    'par_jour', (select coalesce(json_agg(d order by d.day), '[]'::json) from (
        select day, count(*) filter (where kind = 'visit') as visiteurs, count(*) filter (where kind = 'play') as vues
        from analytics_events where day >= since group by day) d),
    'par_plateforme', (select coalesce(json_object_agg(platform, n), '{}'::json) from (
        select coalesce(platform, 'autre') as platform, count(distinct visitor_id) as n
        from analytics_events where kind = 'visit' and day >= since group by 1) p),
    'top_cultes', (select coalesce(json_agg(t), '[]'::json) from (
        select s.id, s.title, count(*) as vues from analytics_events a join sermons s on s.id = a.item_id
        where a.kind = 'play' and a.day >= since group by s.id, s.title order by vues desc limit 10) t)
  );
end $$;
grant execute on function public.admin_stats(integer) to authenticated;

-- ─── 6. STOCKAGE ─────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public) values ('images', 'images', true) on conflict (id) do update set public = true;
insert into storage.buckets (id, name, public) values ('media', 'media', true) on conflict (id) do update set public = true;

drop policy if exists "conacce fichiers lecture" on storage.objects;
create policy "conacce fichiers lecture" on storage.objects for select to anon, authenticated
  using (bucket_id in ('images', 'media'));
drop policy if exists "conacce fichiers admin" on storage.objects;
create policy "conacce fichiers admin" on storage.objects for all to authenticated
  using (bucket_id in ('images', 'media') and public.is_admin())
  with check (bucket_id in ('images', 'media') and public.is_admin());

-- ─── Accès de l'appli aux tables (la sécurité reste assurée par les règles ci-dessus) ───
grant usage on schema public to anon, authenticated;
grant select on public.live_stream, public.radio, public.sermons, public.works, public.home_banners, public.app_settings to anon, authenticated;
grant select, insert, update, delete on public.live_stream, public.radio, public.sermons, public.works, public.home_banners, public.app_settings to authenticated;
grant select, update on public.app_users to authenticated;

-- ─── 7. TEMPS RÉEL ET DONNÉES DE DÉPART ──────────────────────────────────────
do $$ begin
  alter publication supabase_realtime add table public.live_stream;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.radio;
exception when duplicate_object then null; end $$;

insert into public.live_stream (title) select 'Conacce TV' where not exists (select 1 from public.live_stream);
insert into public.radio (name) select 'Radio Dunamis FM' where not exists (select 1 from public.radio);
insert into public.app_settings (id) values (1) on conflict (id) do nothing;

select 'Conacce TV : base prête' as resultat;
