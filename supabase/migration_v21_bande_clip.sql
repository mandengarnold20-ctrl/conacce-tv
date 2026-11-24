-- Conacce TV — v21 : animation de bande propre à chaque clip.
-- tv_programs.band_anim : null ou '' = animation réglée dans l'habillage ;
-- 'haut' (arrive par le haut), 'bas' (arrive par le bas), 'fade' (fondu), 'open' (déploiement).
-- (L'image de bande importée et la taille du texte sont dans tv_branding.config, sans changement de table.)

alter table public.tv_programs add column if not exists band_anim text;
do $$ begin
  alter table public.tv_programs add constraint tv_programs_band_anim_check check (band_anim is null or band_anim in ('', 'haut', 'bas', 'fade', 'open'));
exception when duplicate_object then null; end $$;

-- Restauration / import : garder aussi la priorité, les coupures pub, les jours spéciaux et l'animation de bande.
create or replace function public.tv_replace_programs(v jsonb, why text)
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  if v is null or jsonb_typeof(v) <> 'array' then raise exception 'Fichier de sauvegarde illisible.'; end if;
  perform tv_backup_make('avant ' || why);
  perform set_config('regie.bulk', '1', true);
  delete from tv_programs where true;
  insert into tv_programs (id, title, source, video_url, duration, position, start_at, repeat_daily, repeat_weekly, is_active, created_at,
                           artist, song, kind, show_band, is_priority, ad_breaks, air_extra, special_day_id, band_anim)
  select coalesce(r.id, gen_random_uuid()), r.title, coalesce(r.source, 'youtube'), r.video_url, r.duration,
         coalesce(r.position, 0), r.start_at, coalesce(r.repeat_daily, false), coalesce(r.repeat_weekly, false),
         coalesce(r.is_active, true), coalesce(r.created_at, now()), r.artist, r.song,
         coalesce(r.kind, 'clip'), coalesce(r.show_band, true), coalesce(r.is_priority, false),
         coalesce(r.ad_breaks, '[]'::jsonb), coalesce(r.air_extra, 0), r.special_day_id, r.band_anim
  from jsonb_populate_recordset(null::public.tv_programs, v) r
  where r.title is not null and r.video_url is not null and r.duration > 0;
  get diagnostics n = row_count;
  perform set_config('regie.bulk', '0', true);
  perform regie_log_add('a ' || why || ' la programmation (' || n || ' programmes)');
  return n;
end $$;
revoke all on function public.tv_replace_programs(jsonb, text) from public, anon, authenticated;

select 'bande par clip' as etape, 'ok' as resultat;
