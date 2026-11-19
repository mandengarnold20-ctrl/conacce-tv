-- =============================================================================
--  CONACCE TV — Commentaires du direct (v2)
--  Les messages du jour s'affichent sous la TV. Chaque jour à minuit (heure de
--  Douala / Lagos), ils disparaissent de l'appli et restent en archive dans la
--  page administrateur.
-- =============================================================================

create or replace function public.today_lagos()
returns date language sql stable as $$ select (now() at time zone 'Africa/Lagos')::date $$;

create table if not exists public.live_comments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null check (char_length(btrim(name)) between 1 and 40),
  body        text not null check (char_length(btrim(body)) between 1 and 500),
  visitor_id  uuid,
  day         date not null default public.today_lagos(),
  created_at  timestamptz not null default now()
);
create index if not exists live_comments_day_idx on public.live_comments (day, created_at);

alter table public.live_comments enable row level security;

-- L'appli ne voit que les messages du jour ; l'administrateur voit aussi les archives.
drop policy if exists "commentaires : lecture" on public.live_comments;
create policy "commentaires : lecture" on public.live_comments for select to anon, authenticated
  using (day = public.today_lagos() or public.is_admin());

-- Tout le monde peut écrire un message (du jour uniquement).
drop policy if exists "commentaires : écrire" on public.live_comments;
create policy "commentaires : écrire" on public.live_comments for insert to anon, authenticated
  with check (day = public.today_lagos());

-- Seul l'administrateur peut supprimer.
drop policy if exists "commentaires : admin supprime" on public.live_comments;
create policy "commentaires : admin supprime" on public.live_comments for delete to authenticated
  using (public.is_admin());

-- Anti-spam : un message toutes les 5 secondes par appareil.
create or replace function public.live_comments_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.day := public.today_lagos();
  new.created_at := now();
  if new.visitor_id is not null and exists (
    select 1 from live_comments where visitor_id = new.visitor_id and created_at > now() - interval '5 seconds'
  ) then
    raise exception 'Patientez quelques secondes avant un nouveau message.';
  end if;
  return new;
end $$;
drop trigger if exists live_comments_guard on public.live_comments;
create trigger live_comments_guard before insert on public.live_comments
  for each row execute function public.live_comments_guard();

grant select, insert on public.live_comments to anon, authenticated;
grant delete on public.live_comments to authenticated;

do $$ begin
  alter publication supabase_realtime add table public.live_comments;
exception when duplicate_object then null; end $$;

select 'Commentaires du direct : prêts' as resultat;
