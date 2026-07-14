-- Tracks items that are physically with the delivery worker when an order gets
-- cancelled after it was already packed/out for delivery. Stock is restored to
-- the system count immediately (as before) — this is a separate reconciliation
-- reminder so staff don't forget the physical item still needs to come back.
alter table orders add column if not exists pending_item_return boolean default false;
alter table orders add column if not exists item_returned_at timestamptz;
