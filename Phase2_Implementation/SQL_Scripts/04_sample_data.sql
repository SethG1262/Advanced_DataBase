-- Deterministic, entirely synthetic training data. No random()/extensions/files.
-- Exactly 8 internal staff and 100 independent agents, as in the TRE background.
-- Requires empty tables. A second run fails before inserting anything.
BEGIN;
SET LOCAL search_path = tre, pg_catalog;
SET LOCAL TIME ZONE 'America/Edmonton';
SET CONSTRAINTS ALL DEFERRED;

DO $$
DECLARE t text; populated boolean;
BEGIN
    FOREACH t IN ARRAY ARRAY['client','agent','staff','property','listing','listing_seller',
        'showing','showing_booking','offer','offer_buyer','sale_transaction'] LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM tre.%I)',t) INTO populated;
        IF populated THEN
            RAISE EXCEPTION 'Seed requires empty tre tables; % already contains data. No data was replaced.',t;
        END IF;
    END LOOP;
END $$;

INSERT INTO client (client_id,first_name,last_name,email,phone,created_at)
SELECT g,
    (ARRAY['Alex','Sam','Mei','Jordan','Taylor','Avery','Riley','Morgan','Casey','Jamie'])[(g-1)%10+1],
    (ARRAY['Chen','Patel','Wilson','Nguyen','Martin','Singh','Brown','Lee','Roy','Clark'])[((g-1)/10)%10+1],
    CASE WHEN g%25=0 THEN NULL ELSE format('client%s@example.org',g) END,
    '+1-403-555-' || lpad((100+(g-1)%100)::text,4,'0'),
    timestamptz '2025-01-01 09:00 America/Edmonton' + (g-1)*interval '1 day'
FROM generate_series(1,300) g;

INSERT INTO agent (agent_id,license_number,first_name,last_name,email,phone,is_active)
SELECT g,'TRE-AG-' || lpad(g::text,3,'0'),
    (ARRAY['Quinn','Drew','Robin','Cameron','Reese','Blair','Devon','Skyler','Hayden','Elliot'])[(g-1)%10+1],
    (ARRAY['Adams','Baker','Campbell','Davis','Evans','Foster','Green','Hall','Irwin','Jones'])[((g-1)/10)%10+1],
    format('agent%s@example.org',g),'+1-403-555-' || lpad((100+g-1)::text,4,'0'),g<=95
FROM generate_series(1,100) g;

INSERT INTO staff (staff_id,first_name,last_name,email,role_code,is_active) VALUES
    (1,'Jordan','Park','staff1@example.org','BROKER',true),
    (2,'Avery','Morgan','staff2@example.org','ADMIN',true),
    (3,'Taylor','Reed','staff3@example.org','COORDINATOR',true),
    (4,'Jamie','Brooks','staff4@example.org','COORDINATOR',true),
    (5,'Casey','Ellis','staff5@example.org','ACCOUNTANT',true),
    (6,'Riley','Shaw','staff6@example.org','MARKETING',true),
    (7,'Morgan','Lane','staff7@example.org','ADMIN',true),
    (8,'Alex','Wells','staff8@example.org','COORDINATOR',false);

INSERT INTO property (property_id,property_ref,address_text,municipality,property_type,bedrooms,bathrooms,floor_area_sqm)
SELECT g,'TRE-P-' || lpad(g::text,4,'0'),
    format('%s Training Avenue NW, Unit %s',100+g,1+(g-1)%12),
    (ARRAY['Calgary','Calgary','Calgary','Airdrie','Cochrane'])[(g-1)%5+1],
    (ARRAY['DETACHED','CONDO','TOWNHOUSE','OTHER'])[(g-1)%4+1],
    CASE WHEN g%20=0 THEN NULL ELSE (1+g%5)::smallint END,
    CASE WHEN g%20=0 THEN NULL ELSE 1+(g%6)*0.5 END,
    CASE WHEN g%20=0 THEN NULL ELSE 65+(g%120)*1.75 END
FROM generate_series(1,200) g;

WITH source AS (
    SELECT g,
        CASE WHEN g<=200 THEN g ELSE g-200 END AS property_id,
        CASE WHEN g<=100 THEN date '2026-01-01'+(g-1)*2
             WHEN g<=200 THEN date '2026-09-01'+(g-101)%25
             ELSE date '2025-06-01'+(g-201)*2 END AS listed_on,
        CASE WHEN g<=100 THEN 'SOLD' WHEN g<=150 THEN 'ACTIVE'
             WHEN g<=175 THEN 'UNDER_OFFER' WHEN g<=190 THEN 'DRAFT'
             WHEN g<=200 THEN 'WITHDRAWN' WHEN g<=225 THEN 'EXPIRED'
             ELSE 'WITHDRAWN' END AS status
    FROM generate_series(1,250) g
)
INSERT INTO listing (listing_id,property_id,agent_id,asking_price,listed_on,closed_on,status)
SELECT g,property_id,1+(g-1)%100,275000+(property_id%80)*8250,listed_on,
    CASE WHEN status='SOLD' THEN listed_on+20
         WHEN status IN ('WITHDRAWN','EXPIRED') THEN listed_on+21 END,status
FROM source;

-- 235 non-draft listings with a lead seller, plus 65 joint sellers = 300.
INSERT INTO listing_seller (listing_id,client_id)
SELECT listing_id,1+(listing_id-1)%150 FROM listing WHERE status<>'DRAFT'
UNION ALL SELECT g,150+g FROM generate_series(1,65) g;

WITH source AS (
    SELECT g,CASE WHEN g<=175 THEN g WHEN g<=235 THEN g+15 ELSE g-235 END AS listing_id
    FROM generate_series(1,300) g
), timed AS (
    SELECT s.*,l.agent_id,
        ((CASE WHEN l.status IN ('ACTIVE','UNDER_OFFER') THEN date '2026-10-20'+(l.listing_id%10)::integer
               ELSE l.listed_on+3+(CASE WHEN s.g>235 THEN 1 ELSE 0 END) END)
            + time '09:00') AT TIME ZONE 'America/Edmonton' AS starts_at,
        CASE WHEN s.g%10=0 THEN 'CANCELLED' WHEN l.status IN ('ACTIVE','UNDER_OFFER')
             THEN 'SCHEDULED' ELSE 'COMPLETED' END AS status
    FROM source s JOIN listing l USING (listing_id)
)
INSERT INTO showing (showing_id,listing_id,agent_id,starts_at,ends_at,status)
SELECT g,listing_id,agent_id,starts_at,starts_at+interval '30 minutes',status FROM timed ORDER BY g;

-- First 250 rows include up to three parties per session. The last 50 are
-- retained cancellation/rejection history for the same client/session pairs.
WITH source AS (
    SELECT g,CASE WHEN g<=250 THEN g ELSE g-250 END AS participant,
        CASE WHEN g>250 THEN CASE WHEN g%2=0 THEN 'CANCELLED' ELSE 'REJECTED' END
             WHEN g%13=0 THEN 'REJECTED' WHEN g%11=0 THEN 'CANCELLED'
             WHEN g%3=2 THEN 'PENDING' ELSE 'CONFIRMED' END AS status
    FROM generate_series(1,300) g
)
INSERT INTO showing_booking (booking_id,showing_id,client_id,party_size,status,booked_at)
SELECT x.g,s.showing_id,x.participant,(1+(x.g-1)%3)::smallint,
    CASE WHEN s.status='CANCELLED' THEN 'CANCELLED' ELSE x.status END,
    s.starts_at-interval '2 days'+(x.g%12)*interval '1 minute'
FROM source x JOIN showing s ON s.showing_id=1+(x.participant-1)/3;

WITH source AS (
    SELECT g,CASE WHEN g<=100 THEN g WHEN g<=125 THEN g+50
                  WHEN g<=175 THEN g-25 ELSE g-175 END AS listing_id,
        CASE WHEN g<=125 THEN 'ACCEPTED' WHEN g<=175 THEN 'SUBMITTED'
             WHEN g<=200 THEN 'REJECTED' WHEN g<=225 THEN 'WITHDRAWN' ELSE 'EXPIRED' END AS status
    FROM generate_series(1,250) g
)
INSERT INTO offer (offer_id,listing_id,submitted_by_agent_id,offer_amount,submitted_at,expires_at,accepted_at,status)
SELECT s.g,l.listing_id,1+(s.g+36)%100,round(l.asking_price*(0.96+(s.g%5)*0.01),2),
    (l.listed_on+5+time '10:00') AT TIME ZONE 'America/Edmonton',
    CASE WHEN s.status='SUBMITTED' THEN timestamptz '2026-11-15 18:00 America/Edmonton'
         ELSE (l.listed_on+14+time '18:00') AT TIME ZONE 'America/Edmonton' END,
    CASE WHEN s.status='ACCEPTED' THEN (l.listed_on+10+time '12:00') AT TIME ZONE 'America/Edmonton' END,
    s.status FROM source s JOIN listing l USING (listing_id);

-- All offers have a buyer; 50 have two. Clients may be both buyer and seller.
INSERT INTO offer_buyer (offer_id,client_id)
SELECT g,1+(g+149)%300 FROM generate_series(1,250) g
UNION ALL SELECT g,1+(g+199)%300 FROM generate_series(1,50) g;

INSERT INTO sale_transaction (sale_id,offer_id,coordinator_staff_id,completed_on,sale_price)
SELECT o.offer_id,o.offer_id,CASE WHEN o.offer_id%2=0 THEN 3 ELSE 4 END,l.closed_on,
    round(l.asking_price*(0.94+(o.offer_id%9)*0.01),2)
FROM offer o JOIN listing l USING (listing_id) WHERE o.offer_id<=100;

-- Explicit seed IDs must not leave identity sequences pointing back to 1.
DO $$
DECLARE t text; k text; largest bigint;
BEGIN
    FOREACH t IN ARRAY ARRAY['client','agent','staff','property','listing','showing','showing_booking','offer','sale_transaction'] LOOP
        k := CASE t WHEN 'showing_booking' THEN 'booking_id' WHEN 'sale_transaction' THEN 'sale_id' ELSE t || '_id' END;
        EXECUTE format('SELECT max(%I) FROM tre.%I',k,t) INTO largest;
        PERFORM setval(pg_get_serial_sequence('tre.' || t,k),largest,true);
    END LOOP;
END $$;
SET CONSTRAINTS ALL IMMEDIATE;
COMMIT;
ANALYZE tre.client, tre.agent, tre.staff, tre.property, tre.listing, tre.listing_seller,
    tre.showing, tre.showing_booking, tre.offer, tre.offer_buyer, tre.sale_transaction;
