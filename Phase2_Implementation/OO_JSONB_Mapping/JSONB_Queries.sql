-- Highlight one complete J01-J04 section, or execute all read-only queries.

-- ==================== BEGIN J01 ====================
-- Read nested objects, a decimal string and array lengths for one Listing.
SELECT listing_id,payload->>'status' AS status,
       payload#>>'{property,property_ref}' AS property_ref,
       payload#>>'{property,property_type}' AS property_type,
       payload#>>'{agent,display_name}' AS listing_agent,
       (payload#>>'{asking_price,amount}')::numeric(12,2) AS asking_price_cad,
       jsonb_array_length(payload->'sellers') AS sellers,
       jsonb_array_length(payload->'offers') AS offers
FROM tre_oo.listing_snapshot WHERE listing_id=1;
-- ==================== END J01 ====================

-- ==================== BEGIN J02 ====================
-- JSONB containment can use the GIN jsonb_path_ops index for larger datasets.
SELECT listing_id,payload#>>'{property,property_ref}' AS property_ref,
       (payload#>>'{asking_price,amount}')::numeric(12,2) AS asking_price_cad
FROM tre_oo.listing_snapshot
WHERE payload @> '{"status":"ACTIVE","property":{"property_type":"CONDO"}}'::jsonb
ORDER BY listing_id;
-- ==================== END J02 ====================

-- ==================== BEGIN J03 ====================
-- Expand and regroup a nested seller array: one result row per joint listing.
SELECT s.listing_id,count(*) AS seller_count,
       string_agg(person->>'display_name',', ' ORDER BY (person->>'client_id')::bigint) AS sellers
FROM tre_oo.listing_snapshot s
CROSS JOIN LATERAL jsonb_array_elements(s.payload->'sellers') AS person
WHERE jsonb_array_length(s.payload->'sellers')>1
GROUP BY s.listing_id ORDER BY s.listing_id;
-- ==================== END J03 ====================

-- ==================== BEGIN J04 ====================
-- Read an embedded offer and its embedded buyer array. Acceptance is not completion.
SELECT s.listing_id,(o->>'offer_id')::bigint AS offer_id,o->>'status' AS status,
       (o#>>'{amount,amount}')::numeric(12,2) AS offer_amount_cad,
       jsonb_array_length(o->'buyers') AS buyers
FROM tre_oo.listing_snapshot s
CROSS JOIN LATERAL jsonb_array_elements(s.payload->'offers') AS o
WHERE o->>'status'='ACCEPTED'
ORDER BY s.listing_id;
-- ==================== END J04 ====================
