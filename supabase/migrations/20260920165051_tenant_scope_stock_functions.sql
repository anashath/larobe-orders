-- Phase 1 step 6: tenant-scope process_stock_change and adjust_stock.
--
-- Both are SECURITY DEFINER, so they bypass RLS entirely — the table
-- policies from the previous migration don't protect them. Both were
-- also granted EXECUTE to PUBLIC and anon (pre-existing, not introduced
-- here), meaning any caller, even unauthenticated, could invoke them
-- directly by product_id/order_id. Since we're touching these functions
-- for tenant-scoping anyway, this migration also adds a real
-- authorization check instead of layering tenant checks on top of an
-- open door.
--
-- Also fixes a real bug the previous migration introduced:
-- process_stock_change's INSERT INTO stock_movements didn't supply
-- tenant_id, which is now NOT NULL with no default — that insert would
-- fail outright without this fix.

CREATE OR REPLACE FUNCTION "public"."process_stock_change" (
  "p_product_id" bigint,
  "p_order_id"   bigint,
  "p_change"     integer,
  "p_reason"     text
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.orders where id = p_order_id;
  if v_tenant_id is null then
    raise exception 'Order % not found', p_order_id;
  end if;

  if public.get_my_role(v_tenant_id) is null then
    raise exception 'Not authorized for this tenant';
  end if;

  if not exists (
    select 1 from public.products where id = p_product_id and tenant_id = v_tenant_id
  ) then
    raise exception 'Product % does not belong to order %''s tenant', p_product_id, p_order_id;
  end if;

  update public.products
  set stock_qty = greatest(0, coalesce(stock_qty, 0) + p_change)
  where id = p_product_id;

  update public.orders
  set stock_deducted = (p_change < 0)
  where id = p_order_id;

  insert into public.stock_movements (product_id, order_id, change_qty, reason, tenant_id)
  values (p_product_id, p_order_id, p_change, p_reason, v_tenant_id);
end;
$function$;

CREATE OR REPLACE FUNCTION "public"."adjust_stock" (
  "p_product_id" bigint,
  "p_change"     integer
)
  RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
declare
  v_tenant_id uuid;
begin
  select tenant_id into v_tenant_id from public.products where id = p_product_id;
  if v_tenant_id is null then
    raise exception 'Product % not found', p_product_id;
  end if;

  if public.get_my_role(v_tenant_id) is null then
    raise exception 'Not authorized for this tenant';
  end if;

  update public.products
  set stock_qty = greatest(0, coalesce(stock_qty, 0) + p_change)
  where id = p_product_id;
end;
$function$;
