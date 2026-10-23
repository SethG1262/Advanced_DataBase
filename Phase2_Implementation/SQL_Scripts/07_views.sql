-- Three reusable views. Install after 01-05. Re-running replaces definitions.
BEGIN;
CREATE OR REPLACE VIEW tre.v_active_listings AS
WITH sellers AS (
    SELECT ls.listing_id, count(*) AS seller_count,
           string_agg(c.first_name || ' ' || c.last_name, ', ' ORDER BY c.client_id) AS seller_names
    FROM tre.listing_seller ls JOIN tre.client c USING (client_id)
    GROUP BY ls.listing_id
)
SELECT l.listing_id, l.property_id, p.property_ref, p.address_text,
       p.municipality, p.property_type, l.asking_price, l.listed_on, l.status,
       l.agent_id, a.first_name || ' ' || a.last_name AS listing_agent,
       coalesce(s.seller_count, 0) AS seller_count, s.seller_names
FROM tre.listing l JOIN tre.property p USING (property_id)
JOIN tre.agent a ON a.agent_id = l.agent_id
LEFT JOIN sellers s USING (listing_id)
WHERE l.status IN ('ACTIVE','UNDER_OFFER');

CREATE OR REPLACE VIEW tre.v_showing_capacity AS
WITH bookings AS (
    SELECT showing_id, count(*) AS booking_history_rows,
           count(*) FILTER (WHERE status IN ('PENDING','CONFIRMED')) AS active_parties,
           coalesce(sum(party_size) FILTER (WHERE status IN ('PENDING','CONFIRMED')), 0) AS active_visitors
    FROM tre.showing_booking GROUP BY showing_id
)
SELECT s.showing_id, s.listing_id, l.property_id, s.agent_id,
       s.starts_at, s.ends_at, s.status,
       coalesce(b.booking_history_rows, 0) AS booking_history_rows,
       coalesce(b.active_parties, 0) AS active_parties,
       coalesce(b.active_visitors, 0) AS active_visitors,
       CASE WHEN s.status = 'SCHEDULED' THEN 3 - coalesce(b.active_parties, 0) ELSE 0 END AS bookable_party_slots,
       CASE WHEN s.status <> 'CANCELLED' THEN round(100.0 * coalesce(b.active_parties, 0) / 3, 2) END AS party_utilization_pct
FROM tre.showing s JOIN tre.listing l USING (listing_id)
LEFT JOIN bookings b USING (showing_id);

CREATE OR REPLACE VIEW tre.v_completed_sales AS
SELECT s.sale_id, s.offer_id, o.listing_id, l.property_id,
       l.agent_id AS listing_agent_id, o.submitted_by_agent_id AS offer_agent_id,
       s.coordinator_staff_id, p.municipality, p.property_type,
       l.listed_on, s.completed_on,
       (o.accepted_at AT TIME ZONE 'America/Edmonton')::date AS accepted_local_date,
       l.asking_price, o.offer_amount, s.sale_price,
       s.completed_on - l.listed_on AS days_to_close,
       round(100.0 * s.sale_price / l.asking_price, 2) AS final_to_asking_pct
FROM tre.sale_transaction s JOIN tre.offer o USING (offer_id)
JOIN tre.listing l USING (listing_id) JOIN tre.property p USING (property_id);

COMMENT ON VIEW tre.v_active_listings IS 'One row per ACTIVE/UNDER_OFFER listing; seller rows aggregated before joining.';
COMMENT ON VIEW tre.v_showing_capacity IS 'One row per showing; capacity counts parties; completed/cancelled sessions have zero bookable slots.';
COMMENT ON VIEW tre.v_completed_sales IS 'Exactly one row per completed sale; sale value is not company revenue or commission.';
COMMIT;
