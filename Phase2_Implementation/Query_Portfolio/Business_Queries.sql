-- D0 is a read-only row-count check. Q01-Q12 are the twelve business queries.
-- Highlight one complete labelled section in pgAdmin, or execute all read-only sections.

-- ==================== BEGIN D0 ====================
WITH row_counts AS (
    SELECT 'client' AS table_name, count(*) AS rows FROM tre.client
    UNION ALL SELECT 'agent', count(*) FROM tre.agent
    UNION ALL SELECT 'staff', count(*) FROM tre.staff
    UNION ALL SELECT 'property', count(*) FROM tre.property
    UNION ALL SELECT 'listing', count(*) FROM tre.listing
    UNION ALL SELECT 'listing_seller', count(*) FROM tre.listing_seller
    UNION ALL SELECT 'showing', count(*) FROM tre.showing
    UNION ALL SELECT 'showing_booking', count(*) FROM tre.showing_booking
    UNION ALL SELECT 'offer', count(*) FROM tre.offer
    UNION ALL SELECT 'offer_buyer', count(*) FROM tre.offer_buyer
    UNION ALL SELECT 'sale_transaction', count(*) FROM tre.sale_transaction
)
SELECT table_name, rows, sum(rows) OVER () AS total_business_rows
FROM row_counts ORDER BY table_name;
-- ==================== END D0 ====================

-- ==================== BEGIN Q01 ====================
-- Q01: Which listings are currently being marketed and who is responsible?
-- The view pre-aggregates joint sellers, avoiding duplicate listing rows.
SELECT listing_id, property_ref, municipality, property_type,
       asking_price AS asking_price_cad, status, listing_agent, seller_count, seller_names
FROM tre.v_active_listings
ORDER BY municipality, asking_price DESC, listing_id;
-- ==================== END Q01 ====================

-- ==================== BEGIN Q02 ====================
-- Q02: How did a property's asking price change between listing instances?
WITH history AS (
    SELECT l.*, count(*) OVER (PARTITION BY property_id) AS listing_instances,
           row_number() OVER (PARTITION BY property_id ORDER BY listed_on,listing_id) AS listing_number,
           lag(asking_price) OVER (PARTITION BY property_id ORDER BY listed_on,listing_id) AS previous_asking_price
    FROM tre.listing l
)
SELECT p.property_ref, h.listing_id, h.listing_number, h.status, h.listed_on, h.closed_on,
       h.asking_price, h.previous_asking_price,
       round(100.0*(h.asking_price-h.previous_asking_price)/nullif(h.previous_asking_price,0),2) AS asking_change_pct
FROM history h JOIN tre.property p USING(property_id)
WHERE h.listing_instances > 1
ORDER BY h.property_id, h.listed_on, h.listing_id;
-- ==================== END Q02 ====================

-- ==================== BEGIN Q03 ====================
-- Q03: Which scheduled sessions require agent coverage on October 20-29?
-- Named-zone boundaries and display do not depend on the connection's timezone.
SELECT c.showing_id, c.listing_id, a.agent_id,
       a.first_name || ' ' || a.last_name AS showing_agent, p.property_ref,
       c.starts_at AT TIME ZONE 'America/Edmonton' AS starts_at_calgary,
       c.ends_at AT TIME ZONE 'America/Edmonton' AS ends_at_calgary,
       c.active_parties, c.active_visitors, c.bookable_party_slots
FROM tre.v_showing_capacity c JOIN tre.agent a USING(agent_id)
JOIN tre.property p USING(property_id)
WHERE c.status='SCHEDULED'
  AND c.starts_at >= timestamp '2026-10-20 00:00' AT TIME ZONE 'America/Edmonton'
  AND c.starts_at < timestamp '2026-10-30 00:00' AT TIME ZONE 'America/Edmonton'
ORDER BY c.starts_at, a.agent_id, c.showing_id;
-- ==================== END Q03 ====================

-- ==================== BEGIN Q04 ====================
-- Q04: How many parties/visitors are attached to each showing?
-- Capacity is THREE PARTIES, not three visitors. Historical rows do not consume it.
SELECT showing_id, listing_id, status, booking_history_rows,
       active_parties, active_visitors, bookable_party_slots, party_utilization_pct
FROM tre.v_showing_capacity
ORDER BY showing_id;
-- ==================== END Q04 ====================

-- ==================== BEGIN Q05 ====================
-- Q05: What is each listing's latest submitted offer, if any?
-- Latest submission is distinct from accepted/winning offer; IDs break timestamp ties.
WITH ranked AS (
    SELECT o.*, row_number() OVER (
        PARTITION BY listing_id ORDER BY submitted_at DESC,offer_id DESC) AS rn
    FROM tre.offer o
)
SELECT l.listing_id, l.status AS listing_status, o.offer_id,
       o.status AS latest_offer_status, o.offer_amount,
       o.submitted_at AT TIME ZONE 'America/Edmonton' AS submitted_at_calgary,
       a.first_name || ' ' || a.last_name AS submitting_agent
FROM tre.listing l LEFT JOIN ranked o ON o.listing_id=l.listing_id AND o.rn=1
LEFT JOIN tre.agent a ON a.agent_id=o.submitted_by_agent_id
ORDER BY l.listing_id;
-- ==================== END Q05 ====================

-- ==================== BEGIN Q06 ====================
-- Q06: Which non-draft listings have never received an offer?
-- Grain: one listing. An anti-join avoids NULL-sensitive NOT IN semantics.
SELECT l.listing_id, p.property_ref, l.status, l.listed_on, l.closed_on,
       l.asking_price AS asking_price_cad,
       coalesce(l.closed_on,date '2026-10-19')-l.listed_on AS days_on_market
FROM tre.listing l JOIN tre.property p USING(property_id)
WHERE l.status <> 'DRAFT'
  AND NOT EXISTS (SELECT 1 FROM tre.offer o WHERE o.listing_id=l.listing_id)
ORDER BY days_on_market DESC,l.listing_id;
-- ==================== END Q06 ====================

-- ==================== BEGIN Q07 ====================
-- Q07: Which accepted offers are still waiting for completion on the reference date?
SELECT o.offer_id, o.listing_id, p.property_ref, o.offer_amount,
       (o.accepted_at AT TIME ZONE 'America/Edmonton')::date AS accepted_on_calgary,
       date '2026-10-19'-(o.accepted_at AT TIME ZONE 'America/Edmonton')::date AS waiting_days,
       a.first_name || ' ' || a.last_name AS listing_agent
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.property p USING(property_id) JOIN tre.agent a ON a.agent_id=l.agent_id
WHERE o.status='ACCEPTED'
  AND o.accepted_at < timestamp '2026-10-20 00:00' AT TIME ZONE 'America/Edmonton'
  AND NOT EXISTS (SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id=o.offer_id)
ORDER BY waiting_days DESC,o.offer_id;
-- ==================== END Q07 ====================

-- ==================== BEGIN Q08 ====================
-- Q08: How did completed sale value change each month, including zero-sale months?
-- Sale value means property transaction value, not company revenue/profit.
WITH months AS (
    SELECT d::date AS month_start FROM generate_series(
        timestamp '2026-01-01',timestamp '2026-10-01',interval '1 month') d
), monthly AS (
    SELECT date_trunc('month',completed_on)::date AS month_start,
           count(*) AS completed_sales, sum(sale_price) AS sale_value_cad
    FROM tre.sale_transaction
    WHERE completed_on >= date '2026-01-01' AND completed_on < date '2026-11-01'
    GROUP BY 1
), filled AS (
    SELECT m.month_start, coalesce(s.completed_sales,0) AS completed_sales,
           coalesce(s.sale_value_cad,0)::numeric(16,2) AS sale_value_cad
    FROM months m LEFT JOIN monthly s USING(month_start)
), compared AS (
    SELECT *,lag(sale_value_cad) OVER(ORDER BY month_start) AS previous_month_value
    FROM filled
)
SELECT month_start,completed_sales,sale_value_cad,previous_month_value,
       round(100.0*(sale_value_cad-previous_month_value)/nullif(previous_month_value,0),2) AS month_over_month_pct,
       sum(sale_value_cad) OVER(ORDER BY month_start ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cumulative_sale_value_cad
FROM compared ORDER BY month_start;
-- ==================== END Q08 ====================

-- ==================== BEGIN Q09 ====================
-- Q09: How do listing agents rank by completed sale value in Jan-Oct 2026?
-- Attribution uses LISTING.agent_id, not OFFER.submitted_by_agent_id.
WITH agent_totals AS (
    SELECT a.agent_id,a.first_name || ' ' || a.last_name AS listing_agent,a.is_active,
           count(s.sale_id) AS completed_sales,
           coalesce(sum(s.sale_price),0)::numeric(16,2) AS sale_value_cad
    FROM tre.agent a LEFT JOIN tre.v_completed_sales s
      ON s.listing_agent_id=a.agent_id
     AND s.completed_on>=date '2026-01-01' AND s.completed_on<date '2026-11-01'
    GROUP BY a.agent_id,a.first_name,a.last_name,a.is_active
)
SELECT dense_rank() OVER(ORDER BY sale_value_cad DESC) AS sales_rank,
       agent_id,listing_agent,is_active,completed_sales,sale_value_cad
FROM agent_totals ORDER BY sales_rank,agent_id;
-- ==================== END Q09 ====================

-- ==================== BEGIN Q10 ====================
-- Q10: What are the average close time and final-to-asking ratio for each type?
-- AVG of individual ratios and ratio of totals answer different questions.
SELECT property_type,count(*) AS completed_sales,
       sum(sale_price) AS sale_value_cad,round(avg(sale_price),2) AS avg_sale_price_cad,
       round(avg(days_to_close),2) AS avg_days_to_close,
       round(avg(100.0*sale_price/asking_price),2) AS mean_final_to_asking_pct,
       round(100.0*sum(sale_price)/sum(asking_price),2) AS value_weighted_final_to_asking_pct
FROM tre.v_completed_sales
WHERE completed_on>=date '2026-01-01' AND completed_on<date '2026-11-01'
GROUP BY property_type ORDER BY property_type;
-- ==================== END Q10 ====================

-- ==================== BEGIN Q11 ====================
-- Q11: Which clients participate as both buyers and sellers?
-- Aggregate each relationship first; joining raw many-to-many rows inflates counts.
WITH seller_roles AS (
    SELECT client_id,count(*) AS listings_as_seller FROM tre.listing_seller GROUP BY client_id
), buyer_roles AS (
    SELECT b.client_id,count(*) AS offers_as_buyer,count(s.sale_id) AS completed_purchase_participations
    FROM tre.offer_buyer b LEFT JOIN tre.sale_transaction s USING(offer_id) GROUP BY b.client_id
), bookings AS (
    SELECT client_id,count(*) AS booking_history_rows,
           count(*) FILTER(WHERE status IN ('PENDING','CONFIRMED')) AS active_booking_records
    FROM tre.showing_booking GROUP BY client_id
)
SELECT c.client_id,c.first_name || ' ' || c.last_name AS client_name,
       sr.listings_as_seller,br.offers_as_buyer,br.completed_purchase_participations,
       coalesce(b.booking_history_rows,0) AS booking_history_rows,
       coalesce(b.active_booking_records,0) AS active_booking_records
FROM tre.client c JOIN seller_roles sr USING(client_id) JOIN buyer_roles br USING(client_id)
LEFT JOIN bookings b USING(client_id) ORDER BY c.client_id;
-- ==================== END Q11 ====================

-- ==================== BEGIN Q12 ====================
-- Q12: Which ACTIVE listings ask less than the internal location/type average?
-- This is a synthetic inventory comparison, not a market valuation/appraisal.
WITH benchmarked AS (
    SELECT l.listing_id,p.property_ref,p.municipality,p.property_type,l.asking_price,
           (SELECT avg(peer_l.asking_price)
            FROM tre.listing peer_l JOIN tre.property peer_p USING(property_id)
            WHERE peer_l.status='ACTIVE' AND peer_p.municipality=p.municipality
              AND peer_p.property_type=p.property_type) AS internal_segment_avg
    FROM tre.listing l JOIN tre.property p USING(property_id) WHERE l.status='ACTIVE'
)
SELECT listing_id,property_ref,municipality,property_type,asking_price,
       round(internal_segment_avg,2) AS internal_segment_avg,
       round(asking_price-internal_segment_avg,2) AS asking_minus_avg_cad
FROM benchmarked WHERE asking_price<internal_segment_avg
ORDER BY asking_minus_avg_cad,listing_id;
-- ==================== END Q12 ====================
