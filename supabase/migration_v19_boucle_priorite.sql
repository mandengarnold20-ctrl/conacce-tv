-- Conacce TV — v19 : case « Lire en boucle » et heure exacte prioritaire.
-- 1. tv_channel.loop_repeat : coché (par défaut) = la playlist recommence sans fin ;
--    décoché = elle passe une seule fois depuis son début, puis l'écran d'attente (logo)
--    s'affiche jusqu'au prochain rendez-vous. « Reprendre la playlist au début » la relance.
-- 2. tv_programs.is_priority : un rendez-vous « prioritaire » passe à son heure exacte,
--    même si un autre rendez-vous occupe déjà ce moment.

alter table public.tv_channel add column if not exists loop_repeat boolean not null default true;
alter table public.tv_programs add column if not exists is_priority boolean not null default false;

-- Commandes de la chaîne : + loop_on / loop_off.
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
    -- Le tour de playlist en cours va jusqu'au bout, puis l'écran d'attente.
    select coalesce(sum(duration), 0) into total from tv_programs where is_active and duration > 0 and start_at is null;
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

-- Antenne stable (v15) + boucle décochée : si la playlist est déjà terminée (ou pas encore
-- commencée), une modification ne doit pas la relancer au milieu d'une vidéo.
create or replace function public.tv_keep_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare st text; anc timestamptz; pa timestamptz; t timestamptz; rep boolean;
  kp uuid; ki int; ko double precision; total double precision; x double precision;
begin
  select status, anchor, paused_at, loop_repeat into st, anc, pa, rep from tv_channel where id = 1;
  if not found or st = 'stopped' or anc is null then return null; end if;
  t := case when st = 'paused' and pa is not null then pa else now() end;
  if rep is false then
    select coalesce(sum(duration), 0) into total from tv_programs where is_active and duration > 0 and start_at is null;
    x := extract(epoch from (t - anc));
    if x < 0 then return null; end if;            -- pas encore commencée : rien à garder
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
    -- Playlist terminée (boucle décochée) : elle reste terminée, même si on ajoute des vidéos.
    select coalesce(sum(duration), 0) into total from tv_programs where is_active and duration > 0 and start_at is null;
    update tv_channel set anchor = t - make_interval(secs => total + 1), updated_at = now() where id = 1;
    return null;
  end if;
  offs := (k->>'off')::double precision;
  select count(*) into n from tv_programs where is_active and duration > 0 and start_at is null;
  if n = 0 then return null; end if;
  for r in select id, duration from tv_programs
           where is_active and duration > 0 and start_at is null
           order by position, id loop
    if r.id = (k->>'pid')::uuid then hit := true; exit; end if;
    pre := pre + r.duration; i := i + 1;
  end loop;
  if not hit then
    pre := 0; i := 0; offs := 0;
    for r in select id, duration from tv_programs
             where is_active and duration > 0 and start_at is null
             order by position, id loop
      exit when i >= least((k->>'idx')::int, n - 1);
      pre := pre + r.duration; i := i + 1;
    end loop;
  end if;
  update tv_channel set anchor = t - make_interval(secs => pre + offs), updated_at = now() where id = 1;
  return null;
end $$;

select 'boucle et priorite' as etape, 'ok' as resultat;
