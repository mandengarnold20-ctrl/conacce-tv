-- Conacce TV — v20 : publicités dans un film (coupures à l'instant choisi).
-- • tv_programs.kind = 'pub' : une publicité. Elle ne passe jamais seule (ni boucle, ni rendez-vous),
--   seulement pendant les coupures d'un film.
-- • tv_programs.ad_breaks : les coupures du film, en JSON :
--     [{ "at": secondes dans le film, "ad": identifiant de la pub,
--        "txt": { texte affiché pendant la pub : on, t, x, y, s (taille), d (délai), l (durée) },
--        "res": { « Suite de votre programme sur Conacce TV » à la reprise : on, t, x, y, s, l } }]
-- • tv_programs.air_extra : durée totale des pubs du film (s). Le film occupe l'antenne
--   duration + air_extra secondes : la grille et l'antenne restent exactes pour tout le monde.

do $$ begin
  alter table public.tv_programs drop constraint if exists tv_programs_kind_check;
  alter table public.tv_programs add constraint tv_programs_kind_check check (kind in ('clip', 'emission', 'habillage', 'pub'));
end $$;
alter table public.tv_programs add column if not exists ad_breaks jsonb not null default '[]'::jsonb;
alter table public.tv_programs add column if not exists air_extra integer not null default 0;
do $$ begin
  alter table public.tv_programs add constraint tv_programs_air_extra_check check (air_extra >= 0 and air_extra <= 6 * 3600);
exception when duplicate_object then null; end $$;

-- Boucle : la durée à l'antenne compte les pubs ; les pubs seules ne sont pas dans la boucle.
create or replace function public.tv_loop_at(t timestamptz, anc timestamptz)
returns table (pid uuid, idx int, pos_s double precision)
language plpgsql stable set search_path = public as $$
declare total double precision; x double precision; r record; i int := 0;
begin
  select coalesce(sum(duration + air_extra), 0) into total
  from tv_programs where is_active and duration > 0 and start_at is null and kind <> 'pub';
  if total <= 0 then return; end if;
  x := extract(epoch from (t - anc));
  x := x - total * floor(x / total);
  for r in select id, duration + air_extra as d from tv_programs
           where is_active and duration > 0 and start_at is null and kind <> 'pub'
           order by position, id loop
    if x < r.d then pid := r.id; idx := i; pos_s := x; return next; return; end if;
    x := x - r.d; i := i + 1;
  end loop;
end $$;

create or replace function public.tv_keep_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare st text; anc timestamptz; pa timestamptz; t timestamptz; rep boolean;
  kp uuid; ki int; ko double precision; total double precision; x double precision;
begin
  select status, anchor, paused_at, loop_repeat into st, anc, pa, rep from tv_channel where id = 1;
  if not found or st = 'stopped' or anc is null then return null; end if;
  t := case when st = 'paused' and pa is not null then pa else now() end;
  if rep is false then
    select coalesce(sum(duration + air_extra), 0) into total from tv_programs where is_active and duration > 0 and start_at is null and kind <> 'pub';
    x := extract(epoch from (t - anc));
    if x < 0 then return null; end if;
    if x >= total then
      perform set_config('ctv.keep', json_build_object('ended', true, 't', t)::text, true);
      return null;
    end if;
  end if;
  select l.pid, l.idx, l.pos_s into kp, ki, ko from public.tv_loop_at(t, anc) l;
  if kp is not null then
    perform set_config('ctv.keep', json_build_object('pid', kp, 'idx', ki, 'off', ko, 't', t)::text, true);
  end if;
  return null;
end $$;

create or replace function public.tv_keep_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  raw text := current_setting('ctv.keep', true);
  k json; t timestamptz; pre double precision := 0; hit boolean := false;
  r record; i int := 0; offs double precision; n int; total double precision;
begin
  if raw is null or raw = '' then return null; end if;
  perform set_config('ctv.keep', '', true);
  k := raw::json;
  t := (k->>'t')::timestamptz;
  if (k->>'ended') = 'true' then
    select coalesce(sum(duration + air_extra), 0) into total from tv_programs where is_active and duration > 0 and start_at is null and kind <> 'pub';
    update tv_channel set anchor = t - make_interval(secs => total + 1), updated_at = now() where id = 1;
    return null;
  end if;
  offs := (k->>'off')::double precision;
  select count(*) into n from tv_programs where is_active and duration > 0 and start_at is null and kind <> 'pub';
  if n = 0 then return null; end if;
  for r in select id, duration + air_extra as d from tv_programs
           where is_active and duration > 0 and start_at is null and kind <> 'pub'
           order by position, id loop
    if r.id = (k->>'pid')::uuid then hit := true; exit; end if;
    pre := pre + r.d; i := i + 1;
  end loop;
  if not hit then
    pre := 0; i := 0; offs := 0;
    for r in select id, duration + air_extra as d from tv_programs
             where is_active and duration > 0 and start_at is null and kind <> 'pub'
             order by position, id loop
      exit when i >= least((k->>'idx')::int, n - 1);
      pre := pre + r.d; i := i + 1;
    end loop;
  end if;
  update tv_channel set anchor = t - make_interval(secs => pre + offs), updated_at = now() where id = 1;
  return null;
end $$;

-- « Lire en boucle » décoché : même calcul de durée.
create or replace function public.tv_control(action text)
returns public.tv_channel language plpgsql security definer set search_path = public as $$
declare c public.tv_channel; total double precision; x double precision;
begin
  if not public.can_program() then raise exception 'Votre rôle ne permet pas de piloter la chaîne.'; end if;
  select * into c from public.tv_channel where id = 1 for update;
  if action = 'play' then
    if c.status = 'paused' and c.paused_at is not null then
      update public.tv_channel set status = 'playing', anchor = anchor + (now() - paused_at), paused_at = null, updated_at = now() where id = 1;
    elsif c.status = 'stopped' then
      update public.tv_channel set status = 'playing', anchor = now(), paused_at = null, updated_at = now() where id = 1;
    end if;
    if c.status <> 'playing' then perform regie_log_add('a relancé la chaîne'); end if;
  elsif action = 'pause' then
    if c.status = 'playing' then
      update public.tv_channel set status = 'paused', paused_at = now(), updated_at = now() where id = 1;
      perform regie_log_add('a mis la chaîne en pause');
    end if;
  elsif action = 'stop' then
    update public.tv_channel set status = 'stopped', paused_at = null, updated_at = now() where id = 1;
    perform regie_log_add('a arrêté la chaîne');
  elsif action = 'restart' then
    update public.tv_channel set anchor = now(), updated_at = now() where id = 1;
    perform regie_log_add('a repris la playlist au début');
  elsif action = 'loop_on' then
    update public.tv_channel set loop_repeat = true, updated_at = now() where id = 1;
    perform regie_log_add('a coché « Lire en boucle »');
  elsif action = 'loop_off' then
    select coalesce(sum(duration + air_extra), 0) into total from tv_programs where is_active and duration > 0 and start_at is null and kind <> 'pub';
    x := extract(epoch from (coalesce(c.paused_at, now()) - c.anchor));
    if total > 0 and x >= total then
      update public.tv_channel set anchor = anchor + make_interval(secs => total * floor(x / total)) where id = 1;
    end if;
    update public.tv_channel set loop_repeat = false, updated_at = now() where id = 1;
    perform regie_log_add('a décoché « Lire en boucle »');
  elsif action = 'clear' then
    if not public.is_admin() then raise exception 'Seul un administrateur peut tout effacer.'; end if;
    perform tv_backup_make('avant « Tout effacer »');
    perform set_config('regie.bulk', '1', true);
    delete from public.tv_programs where true;
    perform set_config('regie.bulk', '0', true);
    update public.tv_channel set status = 'playing', paused_at = null, anchor = now(), updated_at = now() where id = 1;
    perform regie_log_add('a supprimé toute la programmation (copie gardée)');
  else
    raise exception 'Commande inconnue : %', action;
  end if;
  select * into c from public.tv_channel where id = 1;
  return c;
end $$;

-- Restauration / import : garder aussi la priorité, les coupures pub et les jours spéciaux.
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
                           artist, song, kind, show_band, is_priority, ad_breaks, air_extra, special_day_id)
  select coalesce(r.id, gen_random_uuid()), r.title, coalesce(r.source, 'youtube'), r.video_url, r.duration,
         coalesce(r.position, 0), r.start_at, coalesce(r.repeat_daily, false), coalesce(r.repeat_weekly, false),
         coalesce(r.is_active, true), coalesce(r.created_at, now()), r.artist, r.song,
         coalesce(r.kind, 'clip'), coalesce(r.show_band, true), coalesce(r.is_priority, false),
         coalesce(r.ad_breaks, '[]'::jsonb), coalesce(r.air_extra, 0), r.special_day_id
  from jsonb_populate_recordset(null::public.tv_programs, v) r
  where r.title is not null and r.video_url is not null and r.duration > 0;
  get diagnostics n = row_count;
  perform set_config('regie.bulk', '0', true);
  perform regie_log_add('a ' || why || ' la programmation (' || n || ' programmes)');
  return n;
end $$;
revoke all on function public.tv_replace_programs(jsonb, text) from public, anon, authenticated;

select 'publicites' as etape, 'ok' as resultat;
