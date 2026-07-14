-- Profile photo support for the drawer hero header.
-- Run this in the Supabase SQL editor (same place you ran the push notification migration).

-- 1. Add avatar_url to profiles (nullable — falls back to initials when empty)
alter table profiles add column if not exists avatar_url text;

-- 2. Create a public "avatars" storage bucket (safe to re-run)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- 3. Storage policies: anyone can view (public bucket read), but a user can only
-- upload/replace/delete files under their OWN folder — client uploads to
-- `${user_id}/avatar.<ext>`, so (storage.foldername(name))[1] must equal auth.uid().
create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

create policy "avatars_insert_own" on storage.objects
  for insert with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_update_own" on storage.objects
  for update using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_delete_own" on storage.objects
  for delete using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- 4. Let a user update their own profile row (full_name, avatar_url) if not already allowed.
-- Skip this if you already have a similar "profiles update own" policy — Postgres will
-- error on a duplicate policy name, safe to ignore/rename in that case.
create policy "profiles_update_own" on profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);
