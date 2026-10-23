-- Read-only seed verification. Any failed assertion raises an error.
BEGIN READ ONLY;
SET LOCAL search_path = tre, pg_catalog;
SET LOCAL TIME ZONE 'America/Edmonton';
DO $$
DECLARE r record; actual bigint;
BEGIN
    FOR r IN SELECT * FROM (VALUES
        ('client',300),('agent',100),('staff',8),('property',200),('listing',250),
        ('listing_seller',300),('showing',300),('showing_booking',300),('offer',250),
        ('offer_buyer',300),('sale_transaction',100)) AS x(table_name,expected) LOOP
        EXECUTE format('SELECT count(*) FROM tre.%I',r.table_name) INTO actual;
        IF actual<>r.expected THEN RAISE EXCEPTION '%: expected %, found %',r.table_name,r.expected,actual; END IF;
    END LOOP;
    IF (SELECT count(*) FROM information_schema.tables WHERE table_schema='tre' AND table_type='BASE TABLE')<>11 THEN
        RAISE EXCEPTION 'Expected exactly 11 business tables'; END IF;
    IF (SELECT count(*) FROM information_schema.columns c
        JOIN information_schema.tables t ON t.table_schema=c.table_schema AND t.table_name=c.table_name
        WHERE c.table_schema='tre' AND t.table_type='BASE TABLE')<>63 THEN
        RAISE EXCEPTION 'Expected the original 63 business attributes'; END IF;
    IF (SELECT count(*) FROM pg_constraint c JOIN pg_namespace n ON n.oid=c.connamespace
        WHERE n.nspname='tre' AND c.contype='f' AND c.confdeltype='r' AND c.confupdtype='r' AND c.convalidated)<>14 THEN
        RAISE EXCEPTION 'Expected 14 validated RESTRICT foreign keys'; END IF;
    IF EXISTS (SELECT 1 FROM listing l WHERE l.status<>'DRAFT'
        AND NOT EXISTS (SELECT 1 FROM listing_seller s WHERE s.listing_id=l.listing_id)) THEN
        RAISE EXCEPTION 'BR03 violation'; END IF;
    IF EXISTS (SELECT property_id FROM listing WHERE status IN ('ACTIVE','UNDER_OFFER') GROUP BY property_id HAVING count(*)>1) THEN
        RAISE EXCEPTION 'BR04 violation'; END IF;
    IF EXISTS (SELECT 1 FROM showing a JOIN showing b ON a.showing_id<b.showing_id
        JOIN listing la ON la.listing_id=a.listing_id JOIN listing lb ON lb.listing_id=b.listing_id
        WHERE a.status<>'CANCELLED' AND b.status<>'CANCELLED'
          AND (a.agent_id=b.agent_id OR la.property_id=lb.property_id)
          AND a.starts_at<b.ends_at AND b.starts_at<a.ends_at) THEN
        RAISE EXCEPTION 'BR07 violation'; END IF;
    IF EXISTS (SELECT showing_id FROM showing_booking WHERE status IN ('PENDING','CONFIRMED')
        GROUP BY showing_id HAVING count(*)>3) THEN RAISE EXCEPTION 'BR09 violation'; END IF;
    IF EXISTS (SELECT showing_id,client_id FROM showing_booking WHERE status IN ('PENDING','CONFIRMED')
        GROUP BY showing_id,client_id HAVING count(*)>1) THEN RAISE EXCEPTION 'BR10 violation'; END IF;
    IF EXISTS (SELECT 1 FROM offer o WHERE NOT EXISTS (SELECT 1 FROM offer_buyer b WHERE b.offer_id=o.offer_id)) THEN
        RAISE EXCEPTION 'BR11 violation'; END IF;
    IF EXISTS (SELECT listing_id FROM offer WHERE status='ACCEPTED' GROUP BY listing_id HAVING count(*)>1) THEN
        RAISE EXCEPTION 'BR13 violation'; END IF;
    IF EXISTS (SELECT 1 FROM sale_transaction s JOIN offer o USING(offer_id)
        WHERE o.status<>'ACCEPTED' OR s.completed_on<(o.accepted_at AT TIME ZONE 'America/Edmonton')::date) THEN
        RAISE EXCEPTION 'BR14/BR15 violation'; END IF;
    IF EXISTS (SELECT 1 FROM sale_transaction s JOIN staff p ON p.staff_id=s.coordinator_staff_id
        WHERE NOT p.is_active OR p.role_code<>'COORDINATOR') THEN RAISE EXCEPTION 'Seed coordinator eligibility violation'; END IF;
    IF EXISTS (SELECT 1 FROM showing_booking b JOIN showing s USING(showing_id)
        WHERE s.status='CANCELLED' AND b.status IN ('PENDING','CONFIRMED')) THEN
        RAISE EXCEPTION 'Seed quality: cancelled showing has active bookings'; END IF;
    RAISE NOTICE 'PASS: 11 tables, 63 attributes, 14 RESTRICT FKs; 2,408 seed rows; cross-table invariants valid.';
END $$;

SELECT 'client' AS table_name,count(*) AS row_count FROM client
UNION ALL SELECT 'agent',count(*) FROM agent
UNION ALL SELECT 'staff',count(*) FROM staff
UNION ALL SELECT 'property',count(*) FROM property
UNION ALL SELECT 'listing',count(*) FROM listing
UNION ALL SELECT 'listing_seller',count(*) FROM listing_seller
UNION ALL SELECT 'showing',count(*) FROM showing
UNION ALL SELECT 'showing_booking',count(*) FROM showing_booking
UNION ALL SELECT 'offer',count(*) FROM offer
UNION ALL SELECT 'offer_buyer',count(*) FROM offer_buyer
UNION ALL SELECT 'sale_transaction',count(*) FROM sale_transaction;
SELECT status,count(*) AS listings FROM listing GROUP BY status ORDER BY status;
SELECT status,count(*) AS offers FROM offer GROUP BY status ORDER BY status;
SELECT status,count(*) AS bookings FROM showing_booking GROUP BY status ORDER BY status;
SELECT count(*) AS accepted_awaiting_completion FROM offer o WHERE status='ACCEPTED'
    AND NOT EXISTS (SELECT 1 FROM sale_transaction s WHERE s.offer_id=o.offer_id);
SELECT count(*) AS relisted_properties FROM (SELECT property_id FROM listing GROUP BY property_id HAVING count(*)>1) x;
SELECT count(*) AS joint_seller_listings FROM (SELECT listing_id FROM listing_seller GROUP BY listing_id HAVING count(*)>1) x;
SELECT count(*) AS joint_buyer_offers FROM (SELECT offer_id FROM offer_buyer GROUP BY offer_id HAVING count(*)>1) x;
COMMIT;
