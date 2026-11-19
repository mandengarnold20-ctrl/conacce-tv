-- Conacce TV — v7 : onglet Audio (section 'audio').
alter table public.sermons drop constraint if exists sermons_section_check;
alter table public.sermons add constraint sermons_section_check check (section in ('cultes', 'conacce', 'louange', 'adoration', 'audio'));
select 'ok' as audio;
