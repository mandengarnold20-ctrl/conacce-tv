-- Conacce TV — v13 : habillage de la chaîne (logo, bandeau d'infos, bande artiste, police).

-- Fiche de chaque programme : artiste, titre de la chanson, type (pour la bibliothèque), bande artiste oui/non.
alter table public.tv_programs add column if not exists artist text;
alter table public.tv_programs add column if not exists song text;
alter table public.tv_programs add column if not exists kind text not null default 'clip';
alter table public.tv_programs add column if not exists show_band boolean not null default true;
do $$ begin
  alter table public.tv_programs add constraint tv_programs_kind_check check (kind in ('clip', 'emission', 'habillage'));
exception when duplicate_object then null; end $$;

-- Réglages d'habillage : une seule ligne, lue par tous, modifiée par la régie.
create table if not exists public.tv_branding (
  id          integer primary key default 1 check (id = 1),
  config      jsonb not null default '{}'::jsonb,
  updated_at  timestamptz not null default now()
);
insert into public.tv_branding (id, config) values (1, '{
  "logo":   {"show": true, "corner": "hd", "size": 100, "opacity": 90, "url": null},
  "ticker": {"show": true, "text": "Merci de suivre Conacce TV · Soutenez la chaîne", "speed": 3, "theme": "nuit", "messages": []},
  "band":   {"show": true, "anim": "slide", "at": 15, "dur": 8, "end": 30},
  "font":   {"name": "Poppins", "url": null}
}'::jsonb) on conflict (id) do nothing;

alter table public.tv_branding enable row level security;
drop policy if exists "habillage : lecture" on public.tv_branding;
create policy "habillage : lecture" on public.tv_branding for select to anon, authenticated using (true);
drop policy if exists "habillage : régie modifie" on public.tv_branding;
create policy "habillage : régie modifie" on public.tv_branding for update to authenticated
  using (public.can_program()) with check (public.can_program());
grant select on public.tv_branding to anon, authenticated;
grant update on public.tv_branding to authenticated;

-- Journal : une ligne au plus toutes les 10 minutes par personne.
create or replace function public.tv_branding_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now();
  if auth.uid() is not null and not exists (
    select 1 from regie_log where user_id = auth.uid() and action = 'a modifié l’habillage' and at > now() - interval '10 minutes') then
    perform regie_log_add('a modifié l’habillage');
  end if;
  return new;
end $$;
drop trigger if exists tv_branding_log on public.tv_branding;
create trigger tv_branding_log before update on public.tv_branding
  for each row execute function public.tv_branding_log();

do $$ begin
  alter publication supabase_realtime add table public.tv_branding;
exception when duplicate_object then null; end $$;

-- Restauration / import : garder aussi artiste, titre, type et bande.
create or replace function public.tv_replace_programs(v jsonb, why text)
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  if v is null or jsonb_typeof(v) <> 'array' then raise exception 'Fichier de sauvegarde illisible.'; end if;
  perform tv_backup_make('avant ' || why);
  perform set_config('regie.bulk', '1', true);
  delete from tv_programs where true;
  insert into tv_programs (id, title, source, video_url, duration, position, start_at, repeat_daily, repeat_weekly, is_active, created_at, artist, song, kind, show_band)
  select coalesce(r.id, gen_random_uuid()), r.title, coalesce(r.source, 'youtube'), r.video_url, r.duration,
         coalesce(r.position, 0), r.start_at, coalesce(r.repeat_daily, false), coalesce(r.repeat_weekly, false),
         coalesce(r.is_active, true), coalesce(r.created_at, now()), r.artist, r.song,
         coalesce(r.kind, 'clip'), coalesce(r.show_band, true)
  from jsonb_populate_recordset(null::public.tv_programs, v) r
  where r.title is not null and r.video_url is not null and r.duration > 0;
  get diagnostics n = row_count;
  perform set_config('regie.bulk', '0', true);
  perform regie_log_add('a ' || why || ' la programmation (' || n || ' programmes)');
  return n;
end $$;
revoke all on function public.tv_replace_programs(jsonb, text) from public, anon, authenticated;

select 'ok' as habillage;
