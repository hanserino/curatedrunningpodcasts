-- User library sync for Best Running Podcasts
-- Run in Supabase SQL editor after creating a project.

create table if not exists public.user_library (
  user_id uuid primary key references auth.users (id) on delete cascade,
  listen_progress jsonb not null default '{}'::jsonb,
  last_listened jsonb,
  favorites jsonb not null default '[]'::jsonb,
  filter_prefs jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- Existing projects: run this if user_library was created before filter_prefs existed.
alter table public.user_library
  add column if not exists filter_prefs jsonb not null default '{}'::jsonb;

alter table public.user_library enable row level security;

create policy "Users can read own library"
  on public.user_library
  for select
  using (auth.uid() = user_id);

create policy "Users can insert own library"
  on public.user_library
  for insert
  with check (auth.uid() = user_id);

create policy "Users can update own library"
  on public.user_library
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "Users can delete own library"
  on public.user_library
  for delete
  using (auth.uid() = user_id);

create or replace function public.set_user_library_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists user_library_set_updated_at on public.user_library;

create trigger user_library_set_updated_at
before update on public.user_library
for each row
execute function public.set_user_library_updated_at();
