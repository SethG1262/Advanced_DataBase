-- Run after 01_schema.sql. PK/UNIQUE indexes are already created by PostgreSQL.
BEGIN;
SET LOCAL search_path = tre, pg_catalog;

-- BR04, BR10 and BR13: conditional uniqueness, including concurrent writes.
CREATE UNIQUE INDEX listing_one_open_per_property_uq ON listing (property_id)
    WHERE status IN ('ACTIVE','UNDER_OFFER');
CREATE UNIQUE INDEX booking_one_active_client_uq ON showing_booking (showing_id, client_id)
    WHERE status IN ('PENDING','CONFIRMED');
CREATE UNIQUE INDEX offer_one_accepted_per_listing_uq ON offer (listing_id)
    WHERE status = 'ACCEPTED';

-- Leading FK columns support referential checks and ordinary joins/history.
CREATE INDEX listing_property_history_idx ON listing (property_id, listed_on DESC);
CREATE INDEX listing_agent_status_idx ON listing (agent_id, status);
CREATE INDEX listing_seller_client_idx ON listing_seller (client_id, listing_id);
CREATE INDEX showing_listing_start_idx ON showing (listing_id, starts_at);
CREATE INDEX showing_agent_start_idx ON showing (agent_id, starts_at);
CREATE INDEX booking_showing_status_idx ON showing_booking (showing_id, status);
CREATE INDEX booking_client_idx ON showing_booking (client_id, showing_id);
CREATE INDEX offer_listing_latest_idx ON offer (listing_id, submitted_at DESC, offer_id DESC);
CREATE INDEX offer_agent_idx ON offer (submitted_by_agent_id);
CREATE INDEX offer_buyer_client_idx ON offer_buyer (client_id, offer_id);
CREATE INDEX sale_coordinator_idx ON sale_transaction (coordinator_staff_id);
CREATE INDEX sale_completed_on_idx ON sale_transaction (completed_on);
CREATE INDEX property_location_type_idx ON property (municipality, property_type);
COMMIT;
