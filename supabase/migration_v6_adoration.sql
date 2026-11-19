-- Conacce TV — v6 : Louange et Adoration séparées (section 'louange' ou 'adoration').
alter table public.sermons drop constraint if exists sermons_section_check;
alter table public.sermons add constraint sermons_section_check check (section in ('cultes', 'conacce', 'louange', 'adoration'));
select 'ok' as adoration;
