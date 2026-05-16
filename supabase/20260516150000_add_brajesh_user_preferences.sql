create table if not exists public.brajesh_user_preferences (
  user_id uuid primary key references auth.users (id) on delete cascade,
  random_theme_selection text[] not null default '{}'::text[],
  random_theme_selection_customized boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint brajesh_user_preferences_random_theme_selection_limit
    check (cardinality(random_theme_selection) <= 200)
);

create or replace function public.brajesh_prepare_user_preferences()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  new.random_theme_selection := coalesce(
    array(
      select selection
      from (
        select min(ord) as ord, lower(trim(selection)) as selection
        from unnest(coalesce(new.random_theme_selection, '{}'::text[])) with ordinality as input(selection, ord)
        where trim(coalesce(selection, '')) <> ''
        group by lower(trim(selection))
      ) deduped
      where selection ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'
      order by ord
    ),
    '{}'::text[]
  );
  new.random_theme_selection_customized := coalesce(new.random_theme_selection_customized, false);
  new.updated_at := timezone('utc', now());

  if tg_op = 'INSERT' and new.created_at is null then
    new.created_at := timezone('utc', now());
  end if;

  return new;
end;
$$;

drop trigger if exists brajesh_user_preferences_prepare on public.brajesh_user_preferences;
create trigger brajesh_user_preferences_prepare
before insert or update on public.brajesh_user_preferences
for each row execute function public.brajesh_prepare_user_preferences();

alter table public.brajesh_user_preferences enable row level security;

drop policy if exists "brajesh_user_preferences_select_own_admin" on public.brajesh_user_preferences;
create policy "brajesh_user_preferences_select_own_admin"
on public.brajesh_user_preferences
for select
to authenticated
using (public.is_brajesh_admin() and auth.uid() = user_id);

drop policy if exists "brajesh_user_preferences_insert_own_admin" on public.brajesh_user_preferences;
create policy "brajesh_user_preferences_insert_own_admin"
on public.brajesh_user_preferences
for insert
to authenticated
with check (public.is_brajesh_admin() and auth.uid() = user_id);

drop policy if exists "brajesh_user_preferences_update_own_admin" on public.brajesh_user_preferences;
create policy "brajesh_user_preferences_update_own_admin"
on public.brajesh_user_preferences
for update
to authenticated
using (public.is_brajesh_admin() and auth.uid() = user_id)
with check (public.is_brajesh_admin() and auth.uid() = user_id);

drop policy if exists "brajesh_user_preferences_delete_own_admin" on public.brajesh_user_preferences;
create policy "brajesh_user_preferences_delete_own_admin"
on public.brajesh_user_preferences
for delete
to authenticated
using (public.is_brajesh_admin() and auth.uid() = user_id);

grant select, insert, update, delete on public.brajesh_user_preferences to authenticated;

with legacy_rows as (
  select
    replace(theme, 'zz-random-theme-selection-pref-', '') as user_id_text,
    body::jsonb as preference_json,
    created_at,
    updated_at,
    id
  from public.brajesh_affirmations
  where theme like 'zz-random-theme-selection-pref-%'
),
ranked_legacy_rows as (
  select
    user_id_text::uuid as user_id,
    preference_json,
    created_at,
    updated_at,
    row_number() over (
      partition by user_id_text
      order by updated_at desc, created_at desc, id desc
    ) as row_number
  from legacy_rows
  where user_id_text ~ '^[0-9a-fA-F-]{36}$'
),
legacy_preferences as (
  select
    user_id,
    case
      when jsonb_typeof(preference_json) = 'array' then
        coalesce(array(select jsonb_array_elements_text(preference_json)), '{}'::text[])
      when jsonb_typeof(preference_json -> 'themes') = 'array' then
        coalesce(array(select jsonb_array_elements_text(preference_json -> 'themes')), '{}'::text[])
      else
        '{}'::text[]
    end as random_theme_selection,
    case
      when jsonb_typeof(preference_json) = 'array' then true
      else coalesce((preference_json ->> 'customized')::boolean, false)
    end as random_theme_selection_customized,
    created_at,
    updated_at
  from ranked_legacy_rows
  where row_number = 1
)
insert into public.brajesh_user_preferences (
  user_id,
  random_theme_selection,
  random_theme_selection_customized,
  created_at,
  updated_at
)
select
  user_id,
  random_theme_selection,
  random_theme_selection_customized,
  created_at,
  updated_at
from legacy_preferences
on conflict (user_id) do update
set
  random_theme_selection = excluded.random_theme_selection,
  random_theme_selection_customized = excluded.random_theme_selection_customized;

delete from public.brajesh_affirmations
where theme like 'zz-random-theme-selection-pref-%';
