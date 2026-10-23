-- Atomic workflow operations built on the existing constraints/triggers.
-- The caller owns BEGIN / COMMIT / ROLLBACK; these procedures never commit.
BEGIN;
CREATE OR REPLACE PROCEDURE tre.accept_offer(IN p_offer_id bigint, IN p_accepted_at timestamptz)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, tre AS $$
DECLARE target_listing bigint; current_offer tre.offer%ROWTYPE; current_listing tre.listing%ROWTYPE;
BEGIN
    IF p_offer_id IS NULL OR p_accepted_at IS NULL OR NOT isfinite(p_accepted_at) THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Supply an offer ID and a finite acceptance timestamp';
    END IF;
    SELECT listing_id INTO target_listing FROM tre.offer WHERE offer_id=p_offer_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Offer not found'; END IF;
    -- Both workflows lock listing first, then offer. Recheck its mapping afterward.
    SELECT * INTO current_listing FROM tre.listing WHERE listing_id=target_listing FOR UPDATE;
    SELECT * INTO current_offer FROM tre.offer WHERE offer_id=p_offer_id FOR UPDATE;
    IF NOT FOUND OR current_offer.listing_id IS DISTINCT FROM target_listing THEN
        RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Offer listing changed concurrently; retry the whole transaction';
    END IF;
    IF current_listing.status <> 'ACTIVE' OR current_offer.status <> 'SUBMITTED' THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Accept a SUBMITTED offer on an ACTIVE listing';
    END IF;
    IF p_accepted_at < current_offer.submitted_at OR
       (current_offer.expires_at IS NOT NULL AND p_accepted_at > current_offer.expires_at) THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Acceptance must be between submission and expiry';
    END IF;
    UPDATE tre.offer SET status='ACCEPTED', accepted_at=p_accepted_at WHERE offer_id=p_offer_id;
    UPDATE tre.listing SET status='UNDER_OFFER', closed_on=NULL WHERE listing_id=target_listing;
END $$;

CREATE OR REPLACE PROCEDURE tre.complete_sale(
    IN p_offer_id bigint, IN p_coordinator_staff_id bigint,
    IN p_completed_on date, IN p_sale_price numeric, INOUT p_sale_id bigint)
LANGUAGE plpgsql SECURITY INVOKER SET search_path = pg_catalog, tre AS $$
DECLARE target_listing bigint; current_offer tre.offer%ROWTYPE; current_listing tre.listing%ROWTYPE;
BEGIN
    IF p_offer_id IS NULL OR p_coordinator_staff_id IS NULL OR p_completed_on IS NULL
       OR NOT isfinite(p_completed_on) OR p_sale_price IS NULL
       OR NOT (p_sale_price > 0 AND p_sale_price < 'Infinity'::numeric) OR p_sale_id IS NOT NULL THEN
        RAISE EXCEPTION USING ERRCODE='22023', MESSAGE='Supply valid sale inputs; pass NULL for the output sale ID';
    END IF;
    SELECT listing_id INTO target_listing FROM tre.offer WHERE offer_id=p_offer_id;
    IF NOT FOUND THEN RAISE EXCEPTION USING ERRCODE='P0002', MESSAGE='Offer not found'; END IF;
    SELECT * INTO current_listing FROM tre.listing WHERE listing_id=target_listing FOR UPDATE;
    SELECT * INTO current_offer FROM tre.offer WHERE offer_id=p_offer_id FOR UPDATE;
    IF NOT FOUND OR current_offer.listing_id IS DISTINCT FROM target_listing THEN
        RAISE EXCEPTION USING ERRCODE='40001', MESSAGE='Offer listing changed concurrently; retry the whole transaction';
    END IF;
    IF current_listing.status <> 'UNDER_OFFER' OR current_offer.status <> 'ACCEPTED' THEN
        RAISE EXCEPTION USING ERRCODE='23514', MESSAGE='Complete an ACCEPTED offer on an UNDER_OFFER listing';
    END IF;
    IF EXISTS (SELECT 1 FROM tre.sale_transaction WHERE offer_id=p_offer_id) THEN
        RAISE EXCEPTION USING ERRCODE='23505', MESSAGE='This offer already has a completed sale';
    END IF;
    -- Existing sale trigger checks Calgary acceptance date and staff eligibility.
    INSERT INTO tre.sale_transaction(offer_id,coordinator_staff_id,completed_on,sale_price)
    VALUES(p_offer_id,p_coordinator_staff_id,p_completed_on,p_sale_price)
    RETURNING sale_id INTO p_sale_id;
    UPDATE tre.listing SET status='SOLD', closed_on=p_completed_on WHERE listing_id=target_listing;
END $$;
COMMENT ON PROCEDURE tre.accept_offer(bigint,timestamptz) IS 'SUBMITTED/ACTIVE -> ACCEPTED/UNDER_OFFER as one caller-owned transaction.';
COMMENT ON PROCEDURE tre.complete_sale(bigint,bigint,date,numeric,bigint) IS 'Insert one validated sale and mark its listing SOLD; INOUT sale ID starts as NULL.';
COMMIT;
