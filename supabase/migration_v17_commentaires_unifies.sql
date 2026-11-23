-- =============================================================================
--  CONACCE TV — Commentaires unifiés (v17)
--  Les commentaires écrits sous la TV vont dans wall_comments : une minute sous
--  la TV, puis pour toujours dans l'onglet « Commentaires » (sauf effacés).
--  On y recopie les anciens commentaires du direct.
-- =============================================================================
alter table public.wall_comments disable trigger wall_comments_guard;
insert into public.wall_comments (name, body, visitor_id, created_at)
select l.name, l.body, l.visitor_id, l.created_at
from public.live_comments l
where not exists (
  select 1 from public.wall_comments w
  where w.created_at = l.created_at and w.name = l.name and w.body = l.body
);
alter table public.wall_comments enable trigger wall_comments_guard;

select count(*) as commentaires from public.wall_comments;
