SELECT property_id,property_type,subclass_summary FROM tre_p3.property_catalog ORDER BY property_id LIMIT 8;

SELECT property_id, features FROM tre_p3.property_features
WHERE features @> '{"outdoor":{"fenced_yard":true}}'::jsonb
ORDER BY property_id;

SELECT property_id, features->'nearby_amenities' AS nearby_amenities
FROM tre_p3.property_features
WHERE features @? '$.nearby_amenities[*] ? (@.distance_m <= 400)'
ORDER BY property_id;

SELECT f.property_id, a.name, a.kind, (j.item->>'distance_m')::numeric AS distance_m
FROM tre_p3.property_features f
CROSS JOIN LATERAL jsonb_array_elements(f.features->'nearby_amenities') AS j(item)
JOIN tre_p3.amenity a ON a.amenity_id=(j.item->>'amenity_id')::numeric::bigint
ORDER BY f.property_id,a.amenity_id;

EXPLAIN (ANALYZE,BUFFERS) SELECT property_id, features FROM tre_p3.property_features
WHERE features @> '{"outdoor":{"fenced_yard":true}}'::jsonb
ORDER BY property_id;

BEGIN;
SELECT tre_p3.set_fenced_yard(1,true);
-- Encapsulated implementation uses jsonb_set; rollback preserves the captured corpus.
ROLLBACK;
