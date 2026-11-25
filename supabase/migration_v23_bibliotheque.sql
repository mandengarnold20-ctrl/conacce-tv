-- Conacce TV — v23 : Bibliothèque des programmes.
-- « Retirer » ne supprime plus un programme : il sort de la diffusion (is_active = false) et reste dans la
-- Bibliothèque de la régie, avec tous ses réglages. La suppression définitive se fait seulement depuis la Bibliothèque.

alter table public.tv_programs add column if not exists archived_at timestamptz;
create index if not exists tv_programs_active_idx on public.tv_programs (is_active);

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
    -- Les copies (classements, jours spéciaux) sont effacées ; les autres programmes vont dans la Bibliothèque.
    delete from public.tv_programs where chart_id is not null or special_day_id is not null;
    update public.tv_programs set is_active = false, archived_at = now() where is_active;
    perform set_config('regie.bulk', '0', true);
    update public.tv_channel set status = 'playing', paused_at = null, anchor = now(), updated_at = now() where id = 1;
    perform regie_log_add('a retiré toute la programmation (programmes gardés dans la Bibliothèque)');
  else
    raise exception 'Commande inconnue : %', action;
  end if;
  select * into c from public.tv_channel where id = 1;
  return c;
end $$;

select 'bibliotheque' as etape, 'ok' as resultat;
