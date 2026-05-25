create table if not exists public.brajesh_themes (
  id uuid primary key default gen_random_uuid(),
  slug text not null,
  display_name text not null,
  is_reserved boolean not null default false,
  sort_order integer not null default 500,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint brajesh_themes_slug_check
    check (slug ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  constraint brajesh_themes_display_name_check
    check (char_length(trim(display_name)) between 1 and 120)
);

create unique index if not exists brajesh_themes_slug_idx
  on public.brajesh_themes (slug);

create unique index if not exists brajesh_themes_display_name_lower_idx
  on public.brajesh_themes (lower(display_name));

create or replace function public.brajesh_prepare_theme()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.slug := public.brajesh_affirmation_theme_slug(coalesce(new.slug, new.display_name));
  new.display_name := regexp_replace(trim(coalesce(new.display_name, '')), E'\\s+', ' ', 'g');

  if new.display_name = '' then
    new.display_name := initcap(replace(new.slug, '-', ' '));
  end if;

  new.updated_at := timezone('utc', now());

  if tg_op = 'INSERT' and new.created_at is null then
    new.created_at := timezone('utc', now());
  end if;

  return new;
end;
$$;

drop trigger if exists brajesh_themes_prepare on public.brajesh_themes;
create trigger brajesh_themes_prepare
before insert or update on public.brajesh_themes
for each row execute function public.brajesh_prepare_theme();

insert into public.brajesh_themes (slug, display_name, is_reserved, sort_order)
values
  ('personal', 'Personal', false, 10),
  ('relationships', 'Relationships', false, 20),
  ('work', 'Work', false, 30),
  ('health', 'Health', false, 40),
  ('long', 'Long', true, 900)
on conflict (slug) do nothing;

insert into public.brajesh_themes (slug, display_name)
select theme_slug, initcap(replace(theme_slug, '-', ' '))
from (
  select distinct public.brajesh_affirmation_theme_slug(theme) as theme_slug
  from public.brajesh_affirmations

  union

  select distinct public.brajesh_affirmation_theme_slug(selection) as theme_slug
  from public.brajesh_user_preferences
  cross join lateral unnest(random_theme_selection) as selection
) existing_themes
where theme_slug <> ''
  and theme_slug <> 'random'
on conflict (slug) do nothing;

alter table public.brajesh_affirmations
  add column if not exists theme_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'brajesh_affirmations_theme_id_fkey'
  ) then
    alter table public.brajesh_affirmations
      add constraint brajesh_affirmations_theme_id_fkey
      foreign key (theme_id)
      references public.brajesh_themes (id);
  end if;
end;
$$;

update public.brajesh_affirmations as affirmation
set theme_id = theme_record.id
from public.brajesh_themes as theme_record
where affirmation.theme_id is null
  and theme_record.slug = public.brajesh_affirmation_theme_slug(affirmation.theme);

alter table public.brajesh_affirmations
  alter column theme_id set not null;

create index if not exists brajesh_affirmations_theme_id_created_at_idx
  on public.brajesh_affirmations (theme_id, created_at);

create or replace function public.brajesh_prepare_affirmation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  resolved_theme_id uuid;
  resolved_theme_slug text;
begin
  if new.theme_id is not null then
    select id, slug
    into resolved_theme_id, resolved_theme_slug
    from public.brajesh_themes
    where id = new.theme_id;

    if resolved_theme_id is null then
      raise exception 'Unknown theme_id for brajesh affirmation.';
    end if;
  else
    resolved_theme_slug := public.brajesh_affirmation_theme_slug(new.theme);

    if resolved_theme_slug = '' then
      raise exception 'Theme is required for brajesh affirmation.';
    end if;

    if resolved_theme_slug = 'random' then
      raise exception 'Random is a display mode and cannot be stored as a theme.';
    end if;

    select id, slug
    into resolved_theme_id, resolved_theme_slug
    from public.brajesh_themes
    where slug = resolved_theme_slug;

    if resolved_theme_id is null then
      insert into public.brajesh_themes (slug, display_name)
      values (
        resolved_theme_slug,
        initcap(replace(resolved_theme_slug, '-', ' '))
      )
      on conflict (slug) do nothing;

      select id, slug
      into resolved_theme_id, resolved_theme_slug
      from public.brajesh_themes
      where slug = resolved_theme_slug;
    end if;
  end if;

  new.theme_id := resolved_theme_id;
  new.theme := resolved_theme_slug;
  new.body := regexp_replace(trim(coalesce(new.body, '')), E'\\r\\n?', E'\\n', 'g');
  new.body_normalized := public.brajesh_normalize_affirmation_text(new.body);
  new.updated_at := timezone('utc', now());

  if tg_op = 'INSERT' and new.created_at is null then
    new.created_at := timezone('utc', now());
  end if;

  return new;
end;
$$;

alter table public.brajesh_themes enable row level security;

drop policy if exists "brajesh_themes_select_admin" on public.brajesh_themes;
create policy "brajesh_themes_select_admin"
on public.brajesh_themes
for select
to authenticated
using (public.is_brajesh_admin());

drop policy if exists "brajesh_themes_insert_admin" on public.brajesh_themes;
create policy "brajesh_themes_insert_admin"
on public.brajesh_themes
for insert
to authenticated
with check (public.is_brajesh_admin());

drop policy if exists "brajesh_themes_update_admin" on public.brajesh_themes;
create policy "brajesh_themes_update_admin"
on public.brajesh_themes
for update
to authenticated
using (public.is_brajesh_admin())
with check (public.is_brajesh_admin());

drop policy if exists "brajesh_themes_delete_admin" on public.brajesh_themes;
create policy "brajesh_themes_delete_admin"
on public.brajesh_themes
for delete
to authenticated
using (public.is_brajesh_admin());
