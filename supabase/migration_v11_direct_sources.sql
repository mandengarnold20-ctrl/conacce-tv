-- Conacce TV — v11 : source du direct (OBS / vMix, ou lien d'un direct YouTube, Facebook, TikTok).
alter table public.live_stream add column if not exists source text not null default 'obs';
alter table public.live_stream add column if not exists live_url text;
do $$ begin
  alter table public.live_stream add constraint live_stream_source_check check (source in ('obs', 'youtube', 'facebook', 'tiktok'));
exception when duplicate_object then null; end $$;
-- Titres YouTube : retire le caractère parasite « ￼ » ajouté par certains copier-coller.
update public.tv_programs set title = btrim(replace(replace(title, U&'\FFFC', ''), U&'\FFFD', '')) where title ~ U&'[\FFFC\FFFD]';
select 'ok' as direct_sources;
