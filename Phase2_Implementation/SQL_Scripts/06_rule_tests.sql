-- Run after 01-05 in a development database. All test ROW changes roll back.
-- Identity sequences are nontransactional: the identity smoke test consumes IDs.
BEGIN;
SET LOCAL search_path = tre, pg_catalog;
SET LOCAL TIME ZONE 'America/Edmonton';
SET LOCAL lock_timeout = '5s';
SET CONSTRAINTS ALL DEFERRED;

CREATE FUNCTION pg_temp.expect_rejection(label text,command text,expected_state text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE actual_state text; error_text text;
BEGIN
    BEGIN
        EXECUTE command;
        SET CONSTRAINTS ALL IMMEDIATE;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS actual_state=RETURNED_SQLSTATE,error_text=MESSAGE_TEXT;
        IF actual_state<>expected_state THEN
            RAISE EXCEPTION 'FAIL %: expected %, got % (%)',label,expected_state,actual_state,error_text;
        END IF;
        RAISE NOTICE 'PASS: % [%]',label,actual_state;
        RETURN;
    END;
    RAISE EXCEPTION 'FAIL %: invalid change was accepted',label;
END $$;

-- Separate fixtures ensure the tests do not depend on accidental seed values.
INSERT INTO property (property_id,property_ref,address_text,municipality,property_type)
SELECT 900000+g,format('TEST-P-%s',g),'Constraint test address','Calgary','CONDO' FROM generate_series(1,6) g;
INSERT INTO listing (listing_id,property_id,agent_id,asking_price,listed_on,status)
SELECT 900000+g,900000+g,g,500000,'2030-01-01',CASE WHEN g=4 THEN 'ACTIVE' ELSE 'DRAFT' END
FROM generate_series(1,6) g;
INSERT INTO listing_seller VALUES (900004,1);
INSERT INTO showing (showing_id,listing_id,agent_id,starts_at,ends_at,status)
SELECT 900000+g,900000+g,g,timestamptz '2030-01-10 08:00 America/Edmonton'+g*interval '1 hour',
    timestamptz '2030-01-10 08:30 America/Edmonton'+g*interval '1 hour','SCHEDULED'
FROM generate_series(1,4) g;
INSERT INTO showing_booking (booking_id,showing_id,client_id,party_size,status) VALUES
    (900001,900001,1,3,'CONFIRMED'),(900002,900001,2,3,'PENDING'),(900003,900001,3,3,'CONFIRMED'),
    (900004,900002,4,1,'PENDING'),(900005,900002,5,1,'CANCELLED');
INSERT INTO offer (offer_id,listing_id,submitted_by_agent_id,offer_amount,submitted_at,expires_at,accepted_at,status) VALUES
    (900001,900001,1,490000,'2030-01-02 10:00 America/Edmonton','2030-01-30 18:00 America/Edmonton','2030-01-05 10:00 America/Edmonton','ACCEPTED'),
    (900002,900002,2,490000,'2030-01-02 10:00 America/Edmonton','2030-01-30 18:00 America/Edmonton',NULL,'SUBMITTED'),
    (900003,900003,3,490000,'2030-01-02 10:00 America/Edmonton','2030-01-30 18:00 America/Edmonton','2030-01-05 10:00 America/Edmonton','ACCEPTED');
INSERT INTO offer_buyer VALUES (900001,1),(900002,2),(900003,3);
INSERT INTO sale_transaction (sale_id,offer_id,coordinator_staff_id,completed_on,sale_price)
VALUES (900001,900001,3,'2030-01-20',488000);
SET CONSTRAINTS ALL IMMEDIATE;
SET CONSTRAINTS ALL DEFERRED;

SELECT pg_temp.expect_rejection('duplicate client email',
    $$INSERT INTO client(first_name,last_name,email,phone) VALUES('Test','Duplicate','client1@example.org','+1-403-555-0199')$$,'23505');
SELECT pg_temp.expect_rejection('email must be normalized',
    $$UPDATE client SET email='UPPER@example.org' WHERE client_id=1$$,'23514');
SELECT pg_temp.expect_rejection('surrogate ID cannot change',
    $$UPDATE client SET client_id=800001 WHERE client_id=1$$,'23514');
SELECT pg_temp.expect_rejection('referenced client deletion',
    $$DELETE FROM client WHERE client_id=1$$,'23001');
SELECT pg_temp.expect_rejection('missing property FK',
    $$UPDATE listing SET property_id=899999 WHERE listing_id=900006$$,'23503');
SELECT pg_temp.expect_rejection('invalid property type',
    $$UPDATE property SET property_type='CASTLE' WHERE property_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('negative bedrooms',
    $$UPDATE property SET bedrooms=-1 WHERE property_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('nonfinite numeric value',
    $$UPDATE property SET bathrooms='NaN' WHERE property_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('nonpositive asking price',
    $$UPDATE listing SET asking_price=0 WHERE listing_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('terminal listing requires closing date',
    $$UPDATE listing SET status='SOLD' WHERE listing_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('closing date before listing date',
    $$UPDATE listing SET status='EXPIRED',closed_on='2029-12-31' WHERE listing_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('one open listing per property',
    $$UPDATE listing SET property_id=900004,status='ACTIVE' WHERE listing_id=900005$$,'23505');
SELECT pg_temp.expect_rejection('non-draft listing needs a seller',
    $$UPDATE listing SET status='ACTIVE' WHERE listing_id=900006$$,'23514');
SELECT pg_temp.expect_rejection('cannot remove last seller',
    $$DELETE FROM listing_seller WHERE listing_id=900004$$,'23514');
SELECT pg_temp.expect_rejection('seller reassignment checks old parent',
    $$UPDATE listing_seller SET listing_id=900005 WHERE listing_id=900004$$,'23514');
SELECT pg_temp.expect_rejection('duplicate seller pair',
    $$INSERT INTO listing_seller VALUES(900004,1)$$,'23505');
SELECT pg_temp.expect_rejection('showing end must follow start',
    $$UPDATE showing SET ends_at=starts_at WHERE showing_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('agent time overlap across properties',
    $$UPDATE showing SET agent_id=1,starts_at='2030-01-10 09:15 America/Edmonton',ends_at='2030-01-10 09:45 America/Edmonton' WHERE showing_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('property overlap across different listings',
    $$INSERT INTO showing(showing_id,listing_id,agent_id,starts_at,ends_at) VALUES(900099,900001,9,'2030-01-10 09:15 America/Edmonton','2030-01-10 09:45 America/Edmonton')$$,'23514');
SELECT pg_temp.expect_rejection('zero party size',
    $$UPDATE showing_booking SET party_size=0 WHERE booking_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('four visitors in one party',
    $$UPDATE showing_booking SET party_size=4 WHERE booking_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('fourth active party',
    $$INSERT INTO showing_booking(booking_id,showing_id,client_id) VALUES(900099,900001,10)$$,'23514');
SELECT pg_temp.expect_rejection('duplicate active client/session',
    $$INSERT INTO showing_booking(booking_id,showing_id,client_id) VALUES(900099,900001,1)$$,'23505');
SELECT pg_temp.expect_rejection('reactivating cancelled booking checks capacity',
    $$UPDATE showing_booking SET showing_id=900001,status='PENDING' WHERE booking_id=900005$$,'23514');
SELECT pg_temp.expect_rejection('moving a booking checks destination capacity',
    $$UPDATE showing_booking SET showing_id=900001 WHERE booking_id=900004$$,'23514');
SELECT pg_temp.expect_rejection('offer requires buyer',
    $$INSERT INTO offer(offer_id,listing_id,submitted_by_agent_id,offer_amount,submitted_at) VALUES(900099,900006,1,400000,'2030-01-03 10:00 America/Edmonton')$$,'23514');
SELECT pg_temp.expect_rejection('cannot remove last buyer',
    $$DELETE FROM offer_buyer WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('buyer reassignment checks old parent',
    $$UPDATE offer_buyer SET offer_id=900003 WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('duplicate buyer pair',
    $$INSERT INTO offer_buyer VALUES(900002,2)$$,'23505');
SELECT pg_temp.expect_rejection('nonpositive offer',
    $$UPDATE offer SET offer_amount=-1 WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('offer expiry before submission',
    $$UPDATE offer SET expires_at=submitted_at WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('acceptance after expiry',
    $$UPDATE offer SET status='ACCEPTED',accepted_at='2030-02-01 12:00 America/Edmonton' WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('unaccepted offer cannot have accepted_at',
    $$UPDATE offer SET accepted_at='2030-01-05 10:00 America/Edmonton' WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('second accepted offer for listing',
    $$UPDATE offer SET listing_id=900001,status='ACCEPTED',accepted_at='2030-01-05 10:00 America/Edmonton' WHERE offer_id=900002$$,'23505');
SELECT pg_temp.expect_rejection('sale requires accepted offer',
    $$INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price) VALUES(900099,900002,3,'2030-01-20',490000)$$,'23514');
SELECT pg_temp.expect_rejection('offer can produce only one sale',
    $$INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price) VALUES(900099,900001,3,'2030-01-20',490000)$$,'23505');
SELECT pg_temp.expect_rejection('sale completion before acceptance',
    $$INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price) VALUES(900099,900003,3,'2030-01-04',490000)$$,'23514');
SELECT pg_temp.expect_rejection('coordinator must have correct role',
    $$INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price) VALUES(900099,900003,1,'2030-01-20',490000)$$,'23514');
SELECT pg_temp.expect_rejection('coordinator must be active',
    $$INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price) VALUES(900099,900003,8,'2030-01-20',490000)$$,'23514');
SELECT pg_temp.expect_rejection('cannot unaccept an offer with a sale',
    $$UPDATE offer SET status='WITHDRAWN',accepted_at=NULL WHERE offer_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('cannot move acceptance after existing sale',
    $$UPDATE offer SET accepted_at='2030-01-25 10:00 America/Edmonton' WHERE offer_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('sale reassignment checks coordinator',
    $$UPDATE sale_transaction SET coordinator_staff_id=1 WHERE sale_id=900001$$,'23514');
SELECT pg_temp.expect_rejection('retain booking history',
    $$DELETE FROM showing_booking WHERE booking_id=900005$$,'23514');
SELECT pg_temp.expect_rejection('retain showing history',
    $$DELETE FROM showing WHERE showing_id=900004$$,'23514');
SELECT pg_temp.expect_rejection('retain offer history',
    $$DELETE FROM offer WHERE offer_id=900002$$,'23514');
SELECT pg_temp.expect_rejection('retain listing history',
    $$DELETE FROM listing WHERE listing_id=900006$$,'23514');
SELECT pg_temp.expect_rejection('retain completed sale',
    $$DELETE FROM sale_transaction WHERE sale_id=900001$$,'23514');

-- Positive boundary cases: adjacent sessions and cancelled overlap are allowed.
INSERT INTO showing(showing_id,listing_id,agent_id,starts_at,ends_at)
VALUES(900010,900001,1,'2030-01-10 09:30 America/Edmonton','2030-01-10 10:00 America/Edmonton');
INSERT INTO showing(showing_id,listing_id,agent_id,starts_at,ends_at,status)
VALUES(900011,900001,1,'2030-01-10 09:00 America/Edmonton','2030-01-10 09:30 America/Edmonton','CANCELLED');
SELECT pg_temp.expect_rejection('reactivating an overlapping showing',
    $$UPDATE showing SET status='SCHEDULED' WHERE showing_id=900011$$,'23514');
-- Reassignment through LISTING must be checked too (different agents here).
UPDATE showing SET starts_at='2030-01-10 09:00 America/Edmonton',ends_at='2030-01-10 09:30 America/Edmonton' WHERE showing_id=900003;
SELECT pg_temp.expect_rejection('listing property reassignment cannot bypass overlap',
    $$UPDATE listing SET property_id=900001 WHERE listing_id=900003$$,'23514');

-- Cancellation frees a party slot; historical client/session pair may recur.
UPDATE showing_booking SET status='CANCELLED' WHERE booking_id=900001;
INSERT INTO showing_booking(booking_id,showing_id,client_id,party_size,status)
VALUES(900010,900001,1,3,'CONFIRMED');
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN RAISE NOTICE 'PASS: adjacent sessions, cancelled overlaps, and rebooking after cancellation'; END $$;
SET CONSTRAINTS ALL DEFERRED;

-- A late Calgary-local acceptance is on the next UTC date. Compare local date,
-- independently of the session's timezone (set to UTC for this test).
SET LOCAL TIME ZONE 'UTC';
UPDATE offer SET accepted_at=timestamp '2030-01-05 23:30' AT TIME ZONE 'America/Edmonton' WHERE offer_id=900003;
INSERT INTO sale_transaction(sale_id,offer_id,coordinator_staff_id,completed_on,sale_price)
VALUES(900010,900003,3,'2030-01-05',488000);
SET CONSTRAINTS ALL IMMEDIATE;
DO $$ BEGIN RAISE NOTICE 'PASS: completion uses Calgary acceptance date even in a UTC session'; END $$;
SET CONSTRAINTS ALL DEFERRED;
UPDATE staff SET is_active=false WHERE staff_id=3;
UPDATE sale_transaction SET sale_price=487000 WHERE sale_id=900010;
UPDATE staff SET is_active=true WHERE staff_id=3;
DO $$ BEGIN RAISE NOTICE 'PASS: later staff retirement does not invalidate historical sales'; END $$;

-- Create a complete graph using generated IDs (all nine identity sequences).
DO $$
DECLARE c bigint; a bigint; st bigint; p bigint; l bigint; sh bigint; b bigint; o bigint; sa bigint;
BEGIN
    INSERT INTO client(first_name,last_name,email,phone) VALUES('Identity','Test',NULL,'+1-403-555-0199') RETURNING client_id INTO c;
    INSERT INTO agent(license_number,first_name,last_name,email,phone)
        VALUES('IDENTITY-TEST','Identity','Agent','identity-agent@example.org','+1-403-555-0199') RETURNING agent_id INTO a;
    INSERT INTO staff(first_name,last_name,email,role_code)
        VALUES('Identity','Staff','identity-staff@example.org','COORDINATOR') RETURNING staff_id INTO st;
    INSERT INTO property(property_ref,address_text,municipality,property_type)
        VALUES('IDENTITY-TEST','Identity test','Calgary','CONDO') RETURNING property_id INTO p;
    INSERT INTO listing(property_id,agent_id,asking_price,listed_on) VALUES(p,a,500000,'2040-01-01') RETURNING listing_id INTO l;
    INSERT INTO listing_seller VALUES(l,c);
    INSERT INTO showing(listing_id,agent_id,starts_at,ends_at)
        VALUES(l,a,'2040-01-02 10:00+00','2040-01-02 10:30+00') RETURNING showing_id INTO sh;
    INSERT INTO showing_booking(showing_id,client_id) VALUES(sh,c) RETURNING booking_id INTO b;
    INSERT INTO offer(listing_id,submitted_by_agent_id,offer_amount,submitted_at,accepted_at,status)
        VALUES(l,a,490000,'2040-01-03 10:00+00','2040-01-04 10:00+00','ACCEPTED') RETURNING offer_id INTO o;
    INSERT INTO offer_buyer VALUES(o,c);
    INSERT INTO sale_transaction(offer_id,coordinator_staff_id,completed_on,sale_price)
        VALUES(o,st,'2040-01-05',488000) RETURNING sale_id INTO sa;
    IF c<=300 OR a<=100 OR st<=8 OR p<=200 OR l<=250 OR sh<=300 OR b<=300 OR o<=250 OR sa<=100 THEN
        RAISE EXCEPTION 'An identity sequence was not advanced past the seeded IDs';
    END IF;
    SET CONSTRAINTS ALL IMMEDIATE;
    RAISE NOTICE 'PASS: all nine identity sequences support implicit-ID inserts';
END $$;
ROLLBACK;
