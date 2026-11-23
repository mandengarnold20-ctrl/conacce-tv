-- Conacce TV — v12 : comptes de la régie (rôles), journal des actions, sauvegardes en ligne.
-- Rôles : administrateur principal (unique, intouchable), administrateur, éditeur, animateur. 5 comptes au plus.

-- ─── 1. Rôles ────────────────────────────────────────────────────────────────
alter table public.app_users add column if not exists staff text;
alter table public.app_users add column if not exists is_owner boolean not null default false;
do $$ begin
  alter table public.app_users add constraint app_users_staff_check check (staff in ('editeur', 'animateur'));
exception when duplicate_object then null; end $$;

create or replace function public.regie_role()
returns text language sql stable security definer set search_path = public as $$
  select case when u.is_owner then 'owner' when u.role = 'admin' then 'admin' else u.staff end
  from app_users u where u.id = auth.uid();
$$;
create or replace function public.can_program()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.regie_role() in ('owner', 'admin', 'editeur'), false);
$$;
create or replace function public.can_live()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(public.regie_role() in ('owner', 'admin', 'animateur'), false);
$$;
grant execute on function public.regie_role(), public.can_program(), public.can_live() to authenticated;

-- ─── 2. Journal des actions ──────────────────────────────────────────────────
create table if not exists public.regie_log (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  user_id  uuid,
  who      text,
  action   text not null
);
alter table public.regie_log enable row level security;
drop policy if exists "journal : admin lit" on public.regie_log;
create policy "journal : admin lit" on public.regie_log for select to authenticated using (public.is_admin());
grant select on public.regie_log to authenticated;

create or replace function public.regie_log_add(p_action text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into regie_log (user_id, who, action)
  values (auth.uid(), (select display_name from app_users where id = auth.uid()), p_action);
end $$;
revoke all on function public.regie_log_add(text) from public, anon, authenticated;

create or replace function public.regie_when(t timestamptz)
returns text language sql immutable as $$
  select to_char(t at time zone 'Africa/Lagos', 'DD/MM à HH24:MI');
$$;

-- ─── 3. Protection du compte principal + limite de 5 comptes ─────────────────
create or replace function public.app_users_guard()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int; nm text; lbl text;
begin
  if new.is_owner is distinct from old.is_owner and auth.uid() is not null then
    raise exception 'L’administrateur principal ne peut pas être changé ici.';
  end if;
  if old.is_owner and new.role <> 'admin' then
    raise exception 'L’administrateur principal garde toujours tous les droits.';
  end if;
  if new.role = 'admin' then new.staff := null; end if;
  if (new.role = 'admin' or new.staff is not null) and not (old.role = 'admin' or old.staff is not null) then
    select count(*) into n from app_users where (role = 'admin' or staff is not null) and id <> new.id;
    if n >= 5 then raise exception 'La régie a déjà 5 comptes. Retirez l’accès à quelqu’un avant d’en ajouter un autre.'; end if;
  end if;
  if new.role is distinct from old.role or new.staff is distinct from old.staff then
    nm := coalesce(new.display_name, 'un compte');
    lbl := case when new.role = 'admin' then 'Administrateur' when new.staff = 'editeur' then 'Éditeur'
                when new.staff = 'animateur' then 'Animateur' else null end;
    perform regie_log_add(case when lbl is null then 'a retiré l’accès à la régie de ' || nm
                               else 'a donné le rôle ' || lbl || ' à ' || nm end);
  end if;
  return new;
end $$;
drop trigger if exists app_users_guard on public.app_users;
create trigger app_users_guard before update on public.app_users
  for each row execute function public.app_users_guard();

-- Liste de l'équipe (avec la dernière connexion), réservée aux administrateurs.
create or replace function public.regie_team()
returns table (id uuid, display_name text, role text, staff text, is_owner boolean, last_sign_in_at timestamptz, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  return query
    select u.id, u.display_name, u.role::text, u.staff, u.is_owner, a.last_sign_in_at, u.created_at
    from app_users u left join auth.users a on a.id = u.id
    where u.role = 'admin' or u.staff is not null
    order by u.is_owner desc, (u.role = 'admin') desc, u.created_at;
end $$;
revoke all on function public.regie_team() from public, anon;
grant execute on function public.regie_team() to authenticated;

-- ─── 4. Droits sur la programmation et le direct ─────────────────────────────
drop policy if exists "programmes tv : lecture" on public.tv_programs;
create policy "programmes tv : lecture" on public.tv_programs for select to anon, authenticated
  using (is_active or public.can_program() or public.can_live());
drop policy if exists "programmes tv : admin écrit" on public.tv_programs;
drop policy if exists "programmes tv : régie écrit" on public.tv_programs;
create policy "programmes tv : régie écrit" on public.tv_programs for all to authenticated
  using (public.can_program()) with check (public.can_program());

create or replace function public.tv_programs_log()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce(current_setting('regie.bulk', true), '') = '1' then return null; end if;
  if tg_op = 'INSERT' then
    perform regie_log_add('a programmé « ' || new.title || ' »' ||
      case when new.start_at is null then ' dans la playlist' else ' le ' || regie_when(new.start_at) end);
  elsif tg_op = 'DELETE' then
    perform regie_log_add('a retiré « ' || old.title || ' »');
  elsif new.start_at is distinct from old.start_at and new.start_at is not null then
    perform regie_log_add('a placé « ' || new.title || ' » le ' || regie_when(new.start_at));
  elsif new.title is distinct from old.title or new.duration is distinct from old.duration
     or new.video_url is distinct from old.video_url or new.is_active is distinct from old.is_active
     or new.repeat_daily is distinct from old.repeat_daily or new.repeat_weekly is distinct from old.repeat_weekly then
    perform regie_log_add('a modifié « ' || new.title || ' »');
  end if;
  return null;
end $$;
drop trigger if exists tv_programs_log on public.tv_programs;
create trigger tv_programs_log after insert or update or delete on public.tv_programs
  for each row execute function public.tv_programs_log();

-- ─── 5. Sauvegardes ──────────────────────────────────────────────────────────
create table if not exists public.tv_backups (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  kind        text not null,
  who         text,
  n           integer not null default 0,
  programs    jsonb not null default '[]'
);
alter table public.tv_backups enable row level security;
drop policy if exists "sauvegardes : admin lit" on public.tv_backups;
create policy "sauvegardes : admin lit" on public.tv_backups for select to authenticated using (public.is_admin());
grant select on public.tv_backups to authenticated;

create or replace function public.tv_backup_make(p_kind text)
returns bigint language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  insert into tv_backups (kind, who, n, programs)
  select p_kind, (select display_name from app_users where id = auth.uid()), count(*),
         coalesce(jsonb_agg(to_jsonb(t) order by t.position, t.created_at), '[]'::jsonb)
  from tv_programs t
  returning id into bid;
  return bid;
end $$;
revoke all on function public.tv_backup_make(text) from public, anon, authenticated;

-- Copie automatique : une par jour (au premier passage dans la régie, et chaque matin si pg_cron est là).
create or replace function public.tv_backup_auto()
returns timestamptz language plpgsql security definer set search_path = public as $$
begin
  if not (public.can_program() or public.can_live()) then return null; end if;
  if not exists (select 1 from tv_backups where kind = 'auto' and created_at > now() - interval '20 hours') then
    perform tv_backup_make('auto');
  end if;
  delete from tv_backups where created_at < now() - interval '30 days';
  delete from regie_log where at < now() - interval '90 days';
  return (select max(created_at) from tv_backups);
end $$;
revoke all on function public.tv_backup_auto() from public, anon;
grant execute on function public.tv_backup_auto() to authenticated;

create or replace function public.tv_backup_now()
returns bigint language plpgsql security definer set search_path = public as $$
declare bid bigint;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  bid := tv_backup_make('manuelle');
  perform regie_log_add('a fait une copie de sauvegarde');
  return bid;
end $$;
revoke all on function public.tv_backup_now() from public, anon;
grant execute on function public.tv_backup_now() to authenticated;

-- Remplace toute la programmation par une liste (copie ou fichier importé), après une copie de sécurité.
create or replace function public.tv_replace_programs(v jsonb, why text)
returns integer language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  if v is null or jsonb_typeof(v) <> 'array' then raise exception 'Fichier de sauvegarde illisible.'; end if;
  perform tv_backup_make('avant ' || why);
  perform set_config('regie.bulk', '1', true);
  delete from tv_programs where true;
  insert into tv_programs (id, title, source, video_url, duration, position, start_at, repeat_daily, repeat_weekly, is_active, created_at)
  select coalesce(r.id, gen_random_uuid()), r.title, coalesce(r.source, 'youtube'), r.video_url, r.duration,
         coalesce(r.position, 0), r.start_at, coalesce(r.repeat_daily, false), coalesce(r.repeat_weekly, false),
         coalesce(r.is_active, true), coalesce(r.created_at, now())
  from jsonb_populate_recordset(null::public.tv_programs, v) r
  where r.title is not null and r.video_url is not null and r.duration > 0;
  get diagnostics n = row_count;
  perform set_config('regie.bulk', '0', true);
  perform regie_log_add('a ' || why || ' la programmation (' || n || ' programmes)');
  return n;
end $$;
revoke all on function public.tv_replace_programs(jsonb, text) from public, anon, authenticated;

create or replace function public.tv_backup_restore(p_id bigint)
returns integer language plpgsql security definer set search_path = public as $$
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs'; end if;
  select programs into v from tv_backups where id = p_id;
  if v is null then raise exception 'Copie introuvable.'; end if;
  return tv_replace_programs(v, 'restauré');
end $$;
create or replace function public.tv_backup_import(p jsonb)
returns integer language plpgsql security definer set search_path = public as $$
begin
  return tv_replace_programs(case when jsonb_typeof(p) = 'object' then p -> 'programs' else p end, 'importé');
end $$;
revoke all on function public.tv_backup_restore(bigint), public.tv_backup_import(jsonb) from public, anon;
grant execute on function public.tv_backup_restore(bigint), public.tv_backup_import(jsonb) to authenticated;

-- ─── 6. Commandes de la chaîne (éditeurs compris ; « tout effacer » : administrateurs, avec copie) ──
create or replace function public.tv_control(action text)
returns public.tv_channel language plpgsql security definer set search_path = public as $$
declare c public.tv_channel;
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
revoke all on function public.tv_control(text) from public, anon;
grant execute on function public.tv_control(text) to authenticated;

-- Direct : administrateurs et animateurs.
create or replace function public.live_control(p_on boolean, p_source text default null, p_url text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.can_live() then raise exception 'Votre rôle ne permet pas de lancer un direct.'; end if;
  if p_on then
    update live_stream set is_live = true, source = coalesce(p_source, source),
      live_url = case when coalesce(p_source, source) = 'obs' then live_url else p_url end, updated_at = now();
    perform regie_log_add('a lancé le direct ' || case coalesce(p_source, 'obs') when 'obs' then 'OBS / vMix'
      when 'youtube' then 'YouTube' when 'facebook' then 'Facebook' else 'TikTok' end);
  else
    update live_stream set is_live = false, updated_at = now();
    perform regie_log_add('a arrêté le direct');
  end if;
end $$;
revoke all on function public.live_control(boolean, text, text) from public, anon;
grant execute on function public.live_control(boolean, text, text) to authenticated;

-- ─── 7. Copie chaque matin à 6 h (heure du Bénin), si l'extension pg_cron est disponible ──
do $$ begin
  create extension if not exists pg_cron with schema pg_catalog;
  perform cron.schedule('conacce-sauvegarde-tv', '0 5 * * *', 'select public.tv_backup_make(''auto'')');
exception when others then raise notice 'pg_cron indisponible : %', sqlerrm; end $$;

-- ─── 8. Administrateur principal : le premier administrateur créé ────────────
update public.app_users set is_owner = true
where id = (select id from public.app_users where role = 'admin' order by created_at limit 1)
  and not exists (select 1 from public.app_users where is_owner);

select display_name, role, is_owner, created_at from public.app_users where role = 'admin' or staff is not null order by created_at;
