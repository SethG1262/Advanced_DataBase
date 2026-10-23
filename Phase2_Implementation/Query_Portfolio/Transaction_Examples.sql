-- Select ONE complete T01-T05 section, excluding this guard, and execute it.
-- T01 COMMITS and belongs in a disposable copy. T02-T05 restore business rows.
DO $$ BEGIN RAISE EXCEPTION 'Select one T01-T05 section. T01 commits; use a disposable database copy.'; END $$;

-- ==================== BEGIN PRECHECK ====================
SELECT o.offer_id,o.status AS offer_status,l.status AS listing_status,EXISTS(SELECT 1 FROM tre.sale_transaction WHERE offer_id=127) AS has_sale FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=127;
-- ==================== END PRECHECK ====================

-- ==================== BEGIN T01 ====================
-- DEMO DATABASE ONLY. This example commits a new completed sale for offer 126.
-- Run once on a fresh copy of the sample data, after SQL scripts 01-05, 07_views.sql and 08_stored_procedures.sql.
BEGIN;
SELECT 'before' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status
FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=126;
CALL tre.accept_offer(126,timestamptz '2026-10-19 10:00 America/Edmonton');
SELECT 'accepted' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status
FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=126;
CALL tre.complete_sale(126,3,date '2026-10-22',433000.00,NULL);
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
SELECT 'committed' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status,
       l.closed_on,s.sale_id,s.sale_price,
       (SELECT count(*) FROM tre.sale_transaction) AS completed_sale_count
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.sale_transaction s USING(offer_id) WHERE o.offer_id=126;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM tre.offer o JOIN tre.listing l USING(listing_id)
        JOIN tre.sale_transaction s USING(offer_id)
        WHERE o.offer_id=126 AND o.status='ACCEPTED' AND l.status='SOLD'
          AND l.closed_on=date '2026-10-22' AND s.sale_price=433000) THEN
        RAISE EXCEPTION 'Atomic commit demonstration failed';
    END IF;
    RAISE NOTICE 'PASS: acceptance, sale INSERT and listing closure committed together';
END $$;
-- ==================== END T01 ====================

-- ==================== BEGIN T02 ====================
-- Safe demonstration: all business row changes are rolled back.
BEGIN;
CALL tre.accept_offer(127,timestamptz '2026-10-19 10:00 America/Edmonton');
CALL tre.complete_sale(127,3,date '2026-10-22',440000.00,NULL);
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'inside_transaction' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status,s.sale_price
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.sale_transaction s USING(offer_id) WHERE o.offer_id=127;
ROLLBACK;
SELECT 'after_rollback' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status,
       EXISTS(SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id=o.offer_id) AS has_sale
FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=127;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM tre.offer o JOIN tre.listing l USING(listing_id)
        WHERE o.offer_id=127 AND o.status='SUBMITTED' AND o.accepted_at IS NULL AND l.status='ACTIVE')
        OR EXISTS (SELECT 1 FROM tre.sale_transaction WHERE offer_id=127) THEN
        RAISE EXCEPTION 'Full rollback demonstration failed';
    END IF;
    RAISE NOTICE 'PASS: ROLLBACK restored the offer/listing and removed the provisional sale';
END $$;
-- ==================== END T02 ====================

-- ==================== BEGIN T03 ====================
-- A savepoint reverses provisional closing while retaining earlier acceptance.
-- Final ROLLBACK restores every row to the original sample state.
BEGIN;
CALL tre.accept_offer(128,timestamptz '2026-10-19 10:00 America/Edmonton');
SAVEPOINT before_closing;
CALL tre.complete_sale(128,3,date '2026-10-22',450000.00,NULL);
SELECT 'provisional_close' AS stage,l.status,s.sale_price
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.sale_transaction s USING(offer_id) WHERE o.offer_id=128;
ROLLBACK TO SAVEPOINT before_closing;
SELECT 'after_savepoint_rollback' AS stage,o.status AS offer_status,l.status AS listing_status,
       EXISTS(SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id=o.offer_id) AS has_sale
FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=128;
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM tre.offer o JOIN tre.listing l USING(listing_id)
        WHERE o.offer_id=128 AND o.status='ACCEPTED' AND l.status='UNDER_OFFER')
        OR EXISTS (SELECT 1 FROM tre.sale_transaction WHERE offer_id=128) THEN
        RAISE EXCEPTION 'Savepoint rollback did not preserve the earlier acceptance';
    END IF;
END $$;
CALL tre.complete_sale(128,3,date '2026-10-23',448000.00,NULL);
SET CONSTRAINTS ALL IMMEDIATE;
SELECT 'revised_close' AS stage,l.status,l.closed_on,s.sale_price
FROM tre.offer o JOIN tre.listing l USING(listing_id)
JOIN tre.sale_transaction s USING(offer_id) WHERE o.offer_id=128;
ROLLBACK;
DO $$ BEGIN RAISE NOTICE 'PASS: savepoint kept acceptance, reversed closing, then allowed revised closing'; END $$;
-- ==================== END T03 ====================

-- ==================== BEGIN T04 ====================
-- A handled exception rolls back a whole PL/pgSQL subtransaction.
-- Both calls belong to that subtransaction, so failed closing reverses acceptance.
BEGIN;
DO $$
DECLARE generated_sale bigint; caught boolean := false; detail text;
BEGIN
    BEGIN
        CALL tre.accept_offer(129,timestamptz '2026-10-19 10:00 America/Edmonton');
        -- Staff 8 is an inactive COORDINATOR: the existing BR16 trigger rejects it.
        CALL tre.complete_sale(129,8,date '2026-10-22',455000.00,generated_sale);
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS detail=MESSAGE_TEXT;
        IF detail NOT LIKE 'BR16:%' THEN RAISE; END IF;
        caught := true;
        RAISE NOTICE 'Expected failure [23514]: %',detail;
    END;
    IF NOT caught THEN RAISE EXCEPTION 'Expected invalid-coordinator failure'; END IF;
    IF NOT EXISTS (SELECT 1 FROM tre.offer o JOIN tre.listing l USING(listing_id)
        WHERE o.offer_id=129 AND o.status='SUBMITTED' AND o.accepted_at IS NULL AND l.status='ACTIVE')
        OR EXISTS (SELECT 1 FROM tre.sale_transaction WHERE offer_id=129) THEN
        RAISE EXCEPTION 'A failed workflow left partial changes';
    END IF;
    RAISE NOTICE 'PASS: failed closing left no accepted offer, changed listing or sale row';
END $$;
SELECT 'after_handled_failure' AS stage,o.offer_id,o.status AS offer_status,l.status AS listing_status,
       EXISTS(SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id=o.offer_id) AS has_sale
FROM tre.offer o JOIN tre.listing l USING(listing_id) WHERE o.offer_id=129;
ROLLBACK;
-- ==================== END T04 ====================

-- ==================== BEGIN T05 ====================
-- Demonstrate the existing deferred booking-capacity trigger, not a new rule.
BEGIN;
SELECT 'before' AS stage,showing_id,active_parties,active_visitors
FROM tre.v_showing_capacity WHERE showing_id=1;
DO $$
DECLARE caught boolean := false; detail text;
BEGIN
    BEGIN
        INSERT INTO tre.showing_booking(showing_id,client_id,party_size,status)
        VALUES(1,300,1,'PENDING');
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN check_violation THEN
        GET STACKED DIAGNOSTICS detail=MESSAGE_TEXT;
        IF detail NOT LIKE 'BR09:%' THEN RAISE; END IF;
        caught := true;
        RAISE NOTICE 'Expected trigger rejection [23514]: %',detail;
    END;
    IF NOT caught OR (SELECT active_parties FROM tre.v_showing_capacity WHERE showing_id=1)<>3 THEN
        RAISE EXCEPTION 'Capacity trigger demonstration failed';
    END IF;
    RAISE NOTICE 'PASS: fourth party rejected and the three existing parties retained';
END $$;
SELECT 'after_rejection' AS stage,showing_id,active_parties,active_visitors
FROM tre.v_showing_capacity WHERE showing_id=1;
ROLLBACK;
-- ==================== END T05 ====================
