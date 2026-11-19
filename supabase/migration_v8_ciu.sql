-- Conacce TV — v8 : vidéos CIU (section 'ciu').
alter table public.sermons drop constraint if exists sermons_section_check;
alter table public.sermons add constraint sermons_section_check check (section in ('cultes', 'conacce', 'ciu', 'louange', 'adoration', 'audio'));
select 'ok' as ciu;
