"""Canonical query definitions shared by runnable examples and evaluation."""
JSON_QUERIES = {
 'J1_containment':"""SELECT property_id, features FROM tre_p3.property_features
WHERE features @> '{"outdoor":{"fenced_yard":true}}'::jsonb
ORDER BY property_id""",
 'J2_jsonpath':"""SELECT property_id, features->'nearby_amenities' AS nearby_amenities
FROM tre_p3.property_features
WHERE features @? '$.nearby_amenities[*] ? (@.distance_m <= 400)'
ORDER BY property_id""",
 'J3_array_join':"""SELECT f.property_id, a.name, a.kind, (j.item->>'distance_m')::numeric AS distance_m
FROM tre_p3.property_features f
CROSS JOIN LATERAL jsonb_array_elements(f.features->'nearby_amenities') AS j(item)
JOIN tre_p3.amenity a ON a.amenity_id=(j.item->>'amenity_id')::numeric::bigint
ORDER BY f.property_id,a.amenity_id"""
}
VECTOR = """SELECT document_id, listing_id, topic, title, body,
 1-(embedding <=> {vec}::public.vector) AS cosine_similarity
FROM tre_p3.listing_document
ORDER BY embedding <=> {vec}::public.vector
LIMIT {limit}"""
COMBINED = """-- Request: Find an active detached home under CAD 700,000 with a fenced
-- yard and a quiet workspace for working from home. Return one best note per listing.
WITH eligible AS MATERIALIZED (
 SELECT d.document_id,d.listing_id,d.title,d.body,l.asking_price,p.address_text,
        tre_p3.property_summary(p.property_id) AS subclass_summary,
        f.features#>'{{outdoor,fenced_yard}}' AS fenced_yard,
        d.embedding <=> {vec}::public.vector AS distance,
        row_number() OVER (PARTITION BY d.listing_id ORDER BY d.embedding <=> {vec}::public.vector,d.document_id) AS listing_rank
 FROM tre_p3.listing_document d
 JOIN tre.listing l USING(listing_id)
 JOIN tre.property p USING(property_id)
 JOIN tre_p3.detached_property dp USING(property_id)
 JOIN tre_p3.property_features f USING(property_id)
 WHERE l.status='ACTIVE' AND l.asking_price<700000
 AND f.features @> '{{"outdoor":{{"fenced_yard":true}},"workspace":{{"separate_office":true}}}}'::jsonb
)
SELECT document_id,listing_id,title,body,asking_price,address_text,subclass_summary,fenced_yard,
       1-distance AS cosine_similarity
FROM eligible WHERE listing_rank=1
ORDER BY distance,listing_id LIMIT 5"""
FILTERED = """SELECT d.document_id,d.listing_id,d.title,d.body,1-(d.embedding <=> {vec}::public.vector) AS cosine_similarity
FROM tre_p3.listing_document d
JOIN tre.listing l USING(listing_id)
WHERE l.status='ACTIVE' AND l.asking_price<700000
ORDER BY d.embedding <=> {vec}::public.vector LIMIT 5"""
HYBRID = """-- Reciprocal rank fusion with k=60; top 100 from each retriever.
WITH v AS MATERIALIZED (
 SELECT document_id,embedding <=> {vec}::public.vector AS distance
 FROM tre_p3.listing_document ORDER BY embedding <=> {vec}::public.vector LIMIT 100
), vr AS (
 SELECT document_id,row_number() OVER (ORDER BY distance,document_id) AS r FROM v
), f AS MATERIALIZED (
 SELECT document_id,ts_rank_cd(search_terms,phraseto_tsquery('english','Juniper Station')) AS score
 FROM tre_p3.listing_document
 WHERE search_terms @@ phraseto_tsquery('english','Juniper Station')
 ORDER BY score DESC,document_id LIMIT 100
), fr AS (
 SELECT document_id,row_number() OVER (ORDER BY score DESC,document_id) AS r FROM f
), ranked AS (
 SELECT coalesce(vr.document_id,fr.document_id) AS document_id,
        coalesce(1.0/(60+vr.r),0)+coalesce(1.0/(60+fr.r),0) AS rrf_score
 FROM vr FULL JOIN fr USING(document_id)
)
SELECT d.document_id,d.listing_id,d.topic,d.title,d.body,ranked.rrf_score
FROM ranked JOIN tre_p3.listing_document d USING(document_id)
ORDER BY rrf_score DESC,document_id LIMIT 5"""
