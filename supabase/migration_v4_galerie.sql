-- Conacce TV — v4 : nouvelles catégories de vidéos + galerie photo (Conacce Chaplains / CIU).

alter type public.sermon_category add value if not exists 'tempsForts';
alter type public.sermon_category add value if not exists 'spots';

create table if not exists public.gallery_photos (
  id           uuid primary key default gen_random_uuid(),
  album        text not null default 'conacce' check (album in ('conacce', 'ciu')),
  image_url    text not null,
  caption      text,
  taken_on     date,
  sort_order   int  not null default 0,
  is_published boolean not null default true,
  created_at   timestamptz not null default now()
);
create index if not exists gallery_photos_album_idx on public.gallery_photos (album, sort_order, taken_on desc);

alter table public.gallery_photos enable row level security;
drop policy if exists "galerie : lecture publique" on public.gallery_photos;
create policy "galerie : lecture publique" on public.gallery_photos for select
  using (is_published or public.is_admin());
drop policy if exists "galerie : admin écrit" on public.gallery_photos;
create policy "galerie : admin écrit" on public.gallery_photos for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
grant select on public.gallery_photos to anon, authenticated;
grant insert, update, delete on public.gallery_photos to authenticated;

select 'ok' as galerie;
