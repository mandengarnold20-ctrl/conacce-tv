-- =============================================================================
--  CONACCE TV — v3 : vidéos par lien (YouTube / Facebook), page « Vidéos Conacce »,
--  messagerie du monde entier (avec le pays), lien du site et e-mail de contact.
-- =============================================================================

-- 1. Deux rubriques de vidéos : les cultes et les vidéos Conacce
alter table public.sermons add column if not exists section text not null default 'cultes';
do $$ begin
  alter table public.sermons add constraint sermons_section_check check (section in ('cultes', 'conacce'));
exception when duplicate_object then null; end $$;
create index if not exists sermons_section_idx on public.sermons (section, is_published, preached_on desc);

-- 2. Site internet et e-mail de la CONACCE
alter table public.app_settings add column if not exists website_url text;
update public.app_settings
   set website_url   = coalesce(website_url, 'https://conaccechaplainsafrique.com'),
       contact_email = coalesce(contact_email, 'contact@conaccechaplainsafrique.com')
 where id = 1;

-- 3. Messagerie : messages envoyés depuis l'appli, partout dans le monde
create table if not exists public.messages (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(btrim(name)) between 1 and 60),
  country_code  text check (country_code ~ '^[A-Z]{2}$'),
  country_name  text check (char_length(country_name) <= 60),
  email         text check (char_length(email) <= 120),
  phone         text check (char_length(phone) <= 30),
  body          text not null check (char_length(btrim(body)) between 1 and 2000),
  is_read       boolean not null default false,
  visitor_id    uuid,
  created_at    timestamptz not null default now()
);
create index if not exists messages_recent_idx on public.messages (created_at desc);
alter table public.messages enable row level security;

drop policy if exists "messages : écrire" on public.messages;
create policy "messages : écrire" on public.messages for insert to anon, authenticated with check (not is_read);
drop policy if exists "messages : admin lit" on public.messages;
create policy "messages : admin lit" on public.messages for select to authenticated using (public.is_admin());
drop policy if exists "messages : admin modifie" on public.messages;
create policy "messages : admin modifie" on public.messages for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists "messages : admin supprime" on public.messages;
create policy "messages : admin supprime" on public.messages for delete to authenticated using (public.is_admin());

-- Anti-spam : un message toutes les 30 secondes par appareil
create or replace function public.messages_guard()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  new.created_at := now();
  new.is_read := false;
  if new.visitor_id is not null and exists (
    select 1 from messages where visitor_id = new.visitor_id and created_at > now() - interval '30 seconds'
  ) then
    raise exception 'Patientez quelques secondes avant un nouveau message.';
  end if;
  return new;
end $$;
drop trigger if exists messages_guard on public.messages;
create trigger messages_guard before insert on public.messages for each row execute function public.messages_guard();

grant insert on public.messages to anon, authenticated;
grant select, update, delete on public.messages to authenticated;

select 'Vidéos par lien et messagerie : prêtes' as resultat;
