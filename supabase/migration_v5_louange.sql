-- Conacce TV — v5 : rubrique « Louange & adoration » (chants dans la table sermons, section = 'louange').
alter table public.sermons drop constraint if exists sermons_section_check;
alter table public.sermons add constraint sermons_section_check check (section in ('cultes', 'conacce', 'louange'));
select 'ok' as louange;
