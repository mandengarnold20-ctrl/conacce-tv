-- Conacce TV — v14 : modèles de journées (étape 3, programmation avancée).
-- Un modèle = une liste de rendez-vous (heure dans la journée + vidéo) qu'on applique à un autre jour.

create table if not exists public.tv_day_templates (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 60),
  items jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  created_by uuid default auth.uid()
);

alter table public.tv_day_templates enable row level security;

drop policy if exists tv_day_templates_read on public.tv_day_templates;
create policy tv_day_templates_read on public.tv_day_templates
  for select to authenticated using (public.regie_role() is not null);

drop policy if exists tv_day_templates_write on public.tv_day_templates;
create policy tv_day_templates_write on public.tv_day_templates
  for insert to authenticated with check (public.can_program());

drop policy if exists tv_day_templates_update on public.tv_day_templates;
create policy tv_day_templates_update on public.tv_day_templates
  for update to authenticated using (public.can_program()) with check (public.can_program());

-- Suppression : l'auteur du modèle ou un administrateur.
drop policy if exists tv_day_templates_delete on public.tv_day_templates;
create policy tv_day_templates_delete on public.tv_day_templates
  for delete to authenticated using (public.can_program() and (created_by = auth.uid() or public.regie_role() in ('owner', 'admin')));

grant select, insert, update, delete on public.tv_day_templates to authenticated;

select 'modeles' as etape, 'ok' as resultat;
