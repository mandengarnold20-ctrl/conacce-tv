-- Conacce TV — v15 : l'antenne ne saute plus quand on modifie la playlist en boucle.
-- La boucle est calée sur une « ancre » horaire. Ajouter, retirer ou réordonner une vidéo changeait
-- la durée totale de la boucle, donc le programme calculé pour « maintenant » : l'antenne sautait
-- (régie et appli). Désormais, à chaque modification, l'ancre est recalculée pour que le programme
-- en cours continue exactement au même endroit. S'il a été retiré, le suivant démarre tout de suite.

-- Programme de la boucle en cours à l'instant t : identifiant, rang et position dans la vidéo (s).
create or replace function public.tv_loop_at(t timestamptz, anc timestamptz)
returns table (pid uuid, idx int, pos_s double precision)
language plpgsql stable set search_path = public as $$
declare
  total double precision;
  x double precision;
  r record;
  i int := 0;
begin
  select coalesce(sum(duration), 0) into total
  from tv_programs where is_active and duration > 0 and start_at is null;
  if total <= 0 then return; end if;
  x := extract(epoch from (t - anc));
  x := x - total * floor(x / total);
  for r in select id, duration from tv_programs
           where is_active and duration > 0 and start_at is null
           order by position, id loop
    if x < r.duration then pid := r.id; idx := i; pos_s := x; return next; return; end if;
    x := x - r.duration; i := i + 1;
  end loop;
end $$;

-- Avant la modification : on note ce qui passe.
create or replace function public.tv_keep_before()
returns trigger language plpgsql security definer set search_path = public as $$
declare st text; anc timestamptz; pa timestamptz; t timestamptz;
  kp uuid; ki int; ko double precision;
begin
  select status, anchor, paused_at into st, anc, pa from tv_channel where id = 1;
  if not found or st = 'stopped' or anc is null then return null; end if;
  t := case when st = 'paused' and pa is not null then pa else now() end;
  select l.pid, l.idx, l.pos_s into kp, ki, ko from public.tv_loop_at(t, anc) l;
  if kp is not null then
    perform set_config('ctv.keep', json_build_object('pid', kp, 'idx', ki, 'off', ko, 't', t)::text, true);
  end if;
  return null;
end $$;

-- Après la modification : on recale l'ancre pour que le même programme continue au même endroit.
create or replace function public.tv_keep_after()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  raw text := current_setting('ctv.keep', true);
  k json; t timestamptz; pre double precision := 0; hit boolean := false;
  r record; i int := 0; offs double precision; n int;
begin
  if raw is null or raw = '' then return null; end if;
  perform set_config('ctv.keep', '', true);
  k := raw::json;
  t := (k->>'t')::timestamptz;
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
    -- Le programme en cours a été retiré : celui qui prend sa place démarre maintenant.
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

drop trigger if exists tv_keep_before on public.tv_programs;
create trigger tv_keep_before before insert or update or delete on public.tv_programs
  for each statement execute function public.tv_keep_before();
drop trigger if exists tv_keep_after on public.tv_programs;
create trigger tv_keep_after after insert or update or delete on public.tv_programs
  for each statement execute function public.tv_keep_after();

select 'antenne_stable' as etape, 'ok' as resultat;
