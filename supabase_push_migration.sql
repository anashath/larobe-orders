-- Web Push subscriptions: one row per browser/device a user has enabled
-- notifications on. role is denormalized from profiles so the Edge Function
-- can target "everyone with role=manager" without an extra join/round-trip.
create table if not exists push_subscriptions (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete cascade not null,
  role text not null,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz default now()
);

alter table push_subscriptions enable row level security;

-- Each user manages only their own subscriptions.
create policy "push_subscriptions_select_own" on push_subscriptions
  for select using (auth.uid() = user_id);
create policy "push_subscriptions_insert_own" on push_subscriptions
  for insert with check (auth.uid() = user_id);
create policy "push_subscriptions_delete_own" on push_subscriptions
  for delete using (auth.uid() = user_id);

-- The Edge Function reads ALL subscriptions (to fan out to managers/delivery)
-- using the service_role key, which bypasses RLS — no extra policy needed for it.
