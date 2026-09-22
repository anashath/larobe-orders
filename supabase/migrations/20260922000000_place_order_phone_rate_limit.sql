-- Phase 2 step 6a: guest checkout safeguard — cap on unpaid/COD orders per
-- phone number (HANDOFF.md §6). Prevents one phone number from flooding a
-- tenant with unpaid orders (accidental double-submits or abuse) without
-- needing any external service.
--
-- Counts orders in the trailing 24h for this tenant + contact where the
-- order is still unpaid-in-effect: COD ('New') or a transfer awaiting slip
-- verification ('Payment pending verification'). Pre-orders are excluded —
-- they require an upfront deposit and go through a separate queue, so they
-- don't fit "unpaid/COD" the way HANDOFF describes this cap.
--
-- Threshold is a local constant (v_recent_cap) rather than a tenant setting
-- since only one tenant exists today — promote to a per-tenant column if a
-- second tenant ever needs a different limit.

CREATE OR REPLACE FUNCTION "public"."place_order" (
  "p_tenant_slug"     text,
  "p_items"           jsonb,   -- [{"product_id": 1, "quantity": 2}, ...]
  "p_customer_name"   text,
  "p_customer_contact" text,
  "p_customer_address" text,
  "p_payment_method"  text,    -- 'transfer' | 'cod' | 'preorder'
  "p_amount_paid"     numeric DEFAULT NULL,
  "p_slip_path"       text DEFAULT NULL,
  "p_deposit_amount"  numeric DEFAULT NULL
)
  RETURNS jsonb
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
DECLARE
  v_tenant_id    uuid;
  v_item         jsonb;
  v_product      record;
  v_subtotal     numeric := 0;
  v_line_total   numeric;
  v_order_id     bigint;
  v_num          integer;
  v_order_date   date := current_date;
  v_status       text;
  v_is_preorder  boolean := (p_payment_method = 'preorder');
  v_product_label text := '';
  v_qty          int;
  v_unit_price   numeric;
  v_payment_note text;
  v_recent_cap   constant int := 3;
  v_recent_count int;
BEGIN
  IF current_setting('request.jwt.claims', true)::json->>'role' IS DISTINCT FROM 'service_role' THEN
    RAISE EXCEPTION 'place_order can only be called by the service role';
  END IF;

  SELECT id INTO v_tenant_id FROM public.tenants WHERE slug = p_tenant_slug AND active;
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Unknown or inactive tenant: %', p_tenant_slug;
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items in order';
  END IF;

  IF p_payment_method NOT IN ('transfer', 'cod', 'preorder') THEN
    RAISE EXCEPTION 'Invalid payment method: %', p_payment_method;
  END IF;

  IF p_customer_name IS NULL OR length(trim(p_customer_name)) = 0 THEN
    RAISE EXCEPTION 'Customer name is required';
  END IF;

  IF p_payment_method IN ('cod', 'transfer') THEN
    SELECT count(*) INTO v_recent_count
      FROM public.orders
      WHERE tenant_id = v_tenant_id
        AND contact = p_customer_contact
        AND status IN ('New', 'Payment pending verification')
        AND created_at >= now() - interval '24 hours';

    IF v_recent_count >= v_recent_cap THEN
      RAISE EXCEPTION 'Too many unpaid orders from this phone number in the last 24 hours. Please contact us directly to place another order.';
    END IF;
  END IF;

  -- Pass 1: validate every item and compute the server-side subtotal
  -- before writing anything.
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'quantity')::int;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Invalid quantity for item';
    END IF;

    SELECT id, name, color, selling_price, price, stock_qty, promo_price, promo_start, promo_end
      INTO v_product
      FROM public.products
      WHERE id = (v_item->>'product_id')::bigint
        AND tenant_id = v_tenant_id
        AND active;

    IF v_product.id IS NULL THEN
      RAISE EXCEPTION 'Product % not found for this tenant', (v_item->>'product_id');
    END IF;

    IF NOT v_is_preorder AND v_product.stock_qty < v_qty THEN
      RAISE EXCEPTION 'Insufficient stock for %', v_product.name;
    END IF;

    v_unit_price := COALESCE(v_product.selling_price, v_product.price, 0);
    IF v_product.promo_price IS NOT NULL
       AND (v_product.promo_start IS NULL OR current_date >= v_product.promo_start)
       AND (v_product.promo_end IS NULL OR current_date <= v_product.promo_end) THEN
      v_unit_price := v_product.promo_price;
    END IF;

    v_line_total := v_unit_price * v_qty;
    v_subtotal := v_subtotal + v_line_total;
    v_product_label := v_product_label || CASE WHEN v_product_label = '' THEN '' ELSE ', ' END
      || v_product.name
      || CASE WHEN v_product.color IS NOT NULL THEN ' - ' || v_product.color ELSE '' END
      || CASE WHEN v_qty > 1 THEN ' x' || v_qty ELSE '' END;
  END LOOP;

  v_status := CASE p_payment_method
    WHEN 'cod' THEN 'New'
    WHEN 'transfer' THEN 'Payment pending verification'
    WHEN 'preorder' THEN 'Pre-order'
  END;

  v_payment_note := CASE p_payment_method
    WHEN 'transfer' THEN 'Amount paid: ' || COALESCE(p_amount_paid::text, '0')
      || CASE WHEN p_amount_paid IS DISTINCT FROM v_subtotal THEN ' (order total: ' || v_subtotal::text || ')' ELSE '' END
      || CASE WHEN p_slip_path IS NOT NULL THEN ' | Slip: ' || p_slip_path ELSE '' END
    WHEN 'preorder' THEN 'Deposit: ' || COALESCE(p_deposit_amount::text, '0')
    ELSE NULL
  END;

  SELECT COALESCE(max(num), 0) + 1 INTO v_num
    FROM public.orders WHERE order_date = v_order_date AND tenant_id = v_tenant_id;

  INSERT INTO public.orders (
    tenant_id, num, customer_name, contact, product, price, status, source,
    order_date, order_time, payment, payment_done, notes, delivery
  ) VALUES (
    v_tenant_id, v_num, p_customer_name, p_customer_contact, v_product_label, v_subtotal, v_status, 'web',
    v_order_date, to_char(now(), 'HH24:MI'), p_payment_method, (p_payment_method = 'cod'),
    v_payment_note, p_customer_address
  )
  RETURNING id INTO v_order_id;

  -- Pass 2: write line items and deduct stock (skipped for pre-orders).
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_qty := (v_item->>'quantity')::int;

    SELECT id, name, color, selling_price, price, promo_price, promo_start, promo_end
      INTO v_product
      FROM public.products
      WHERE id = (v_item->>'product_id')::bigint AND tenant_id = v_tenant_id;

    v_unit_price := COALESCE(v_product.selling_price, v_product.price, 0);
    IF v_product.promo_price IS NOT NULL
       AND (v_product.promo_start IS NULL OR current_date >= v_product.promo_start)
       AND (v_product.promo_end IS NULL OR current_date <= v_product.promo_end) THEN
      v_unit_price := v_product.promo_price;
    END IF;

    INSERT INTO public.order_items (tenant_id, order_id, product_id, product_name, unit_price, unit_cost, quantity, line_total)
    VALUES (
      v_tenant_id, v_order_id, v_product.id,
      v_product.name || COALESCE(' - ' || v_product.color, ''),
      v_unit_price, 0, v_qty, v_unit_price * v_qty
    );

    IF NOT v_is_preorder THEN
      UPDATE public.products SET stock_qty = GREATEST(0, stock_qty - v_qty) WHERE id = v_product.id;
      INSERT INTO public.stock_movements (tenant_id, product_id, order_id, change_qty, reason)
      VALUES (v_tenant_id, v_product.id, v_order_id, -v_qty, 'web_order');
    END IF;
  END LOOP;

  INSERT INTO public.order_activity (tenant_id, order_id, user_id, user_name, action)
  VALUES (v_tenant_id, v_order_id, NULL, 'Storefront', 'created (source: web)');

  RETURN jsonb_build_object('order_id', v_order_id, 'order_num', v_num, 'total', v_subtotal, 'status', v_status);
END;
$function$;
