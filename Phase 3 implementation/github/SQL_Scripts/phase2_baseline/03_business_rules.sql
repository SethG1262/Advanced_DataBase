-- Cross-row and cross-table Phase 1 rules; no additional business tables/columns.
-- Parent no-op UPDATEs intentionally obtain a write lock AND create a row version.
-- This serializes competing child writes at READ COMMITTED and makes a stale
-- REPEATABLE READ/SERIALIZABLE writer abort (40001) rather than miss a conflict.
-- Retry the entire transaction after 40001 or 40P01. Trigger functions are VOLATILE.
BEGIN;
SET LOCAL search_path = tre, pg_catalog;

CREATE FUNCTION tre.keep_surrogate_id() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
BEGIN
    IF to_jsonb(NEW) -> TG_ARGV[0] IS DISTINCT FROM to_jsonb(OLD) -> TG_ARGV[0] THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR01/BR18: surrogate identifiers are immutable';
    END IF;
    RETURN NEW;
END $$;

DO $$
DECLARE t text; k text;
BEGIN
    FOREACH t IN ARRAY ARRAY['client','agent','staff','property','listing','showing','showing_booking','offer','sale_transaction'] LOOP
        k := CASE t WHEN 'showing_booking' THEN 'booking_id' WHEN 'sale_transaction' THEN 'sale_id' ELSE t || '_id' END;
        EXECUTE format('CREATE TRIGGER a_keep_id BEFORE UPDATE ON tre.%I FOR EACH ROW EXECUTE FUNCTION tre.keep_surrogate_id(%L)', t, k);
    END LOOP;
END $$;

CREATE FUNCTION tre.retain_history() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
BEGIN
    -- Retain all business event rows, including drafts. This also prevents
    -- reopening a cancelled row and then deleting it to erase its history.
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR18: retain business event records; use status updates';
END $$;

DO $$
DECLARE t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['listing','showing','showing_booking','offer','sale_transaction'] LOOP
        EXECUTE format('CREATE TRIGGER b_retain_history BEFORE DELETE ON tre.%I FOR EACH ROW EXECUTE FUNCTION tre.retain_history()', t);
    END LOOP;
END $$;

-- Lock both old/new parent IDs in ascending order when association rows move.
CREATE FUNCTION tre.lock_association_parents() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE old_id bigint; new_id bigint; parent_id bigint;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_id := (to_jsonb(OLD) ->> TG_ARGV[1])::bigint; END IF;
    IF TG_OP <> 'DELETE' THEN new_id := (to_jsonb(NEW) ->> TG_ARGV[1])::bigint; END IF;
    FOR parent_id IN SELECT DISTINCT v FROM unnest(ARRAY[old_id,new_id]) v WHERE v IS NOT NULL ORDER BY v LOOP
        IF TG_ARGV[0] = 'listing' THEN
            UPDATE tre.listing SET status = status WHERE listing_id = parent_id;
        ELSIF TG_ARGV[0] = 'offer' THEN
            UPDATE tre.offer SET status = status WHERE offer_id = parent_id;
        ELSE
            UPDATE tre.showing SET status = status WHERE showing_id = parent_id;
        END IF;
    END LOOP;
    IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER c_lock_seller_parent BEFORE INSERT OR UPDATE OR DELETE ON listing_seller
    FOR EACH ROW EXECUTE FUNCTION tre.lock_association_parents('listing','listing_id');
CREATE TRIGGER c_lock_buyer_parent BEFORE INSERT OR UPDATE OR DELETE ON offer_buyer
    FOR EACH ROW EXECUTE FUNCTION tre.lock_association_parents('offer','offer_id');
CREATE TRIGGER c_lock_booking_parent BEFORE INSERT OR UPDATE OR DELETE ON showing_booking
    FOR EACH ROW EXECUTE FUNCTION tre.lock_association_parents('showing','showing_id');

CREATE FUNCTION tre.check_minimum_participants() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE old_id bigint; new_id bigint; parent_id bigint;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_id := (to_jsonb(OLD) ->> TG_ARGV[1])::bigint; END IF;
    IF TG_OP <> 'DELETE' THEN new_id := (to_jsonb(NEW) ->> TG_ARGV[1])::bigint; END IF;
    FOR parent_id IN SELECT DISTINCT v FROM unnest(ARRAY[old_id,new_id]) v WHERE v IS NOT NULL LOOP
        IF TG_ARGV[0] = 'listing' THEN
            IF EXISTS (SELECT 1 FROM tre.listing l WHERE l.listing_id = parent_id AND l.status <> 'DRAFT'
                AND NOT EXISTS (SELECT 1 FROM tre.listing_seller s WHERE s.listing_id = l.listing_id)) THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = format('BR03: non-draft listing %s needs a seller',parent_id);
            END IF;
        ELSE
            IF EXISTS (SELECT 1 FROM tre.offer o WHERE o.offer_id = parent_id
                AND NOT EXISTS (SELECT 1 FROM tre.offer_buyer b WHERE b.offer_id = o.offer_id)) THEN
                RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = format('BR11: offer %s needs a buyer',parent_id);
            END IF;
        END IF;
    END LOOP;
    RETURN NULL;
END $$;

-- Deferred checks permit parent + child insertion together in one transaction.
CREATE CONSTRAINT TRIGGER listing_requires_seller AFTER INSERT OR UPDATE ON listing
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION tre.check_minimum_participants('listing','listing_id');
CREATE CONSTRAINT TRIGGER seller_change_preserves_minimum AFTER INSERT OR UPDATE OR DELETE ON listing_seller
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION tre.check_minimum_participants('listing','listing_id');
CREATE CONSTRAINT TRIGGER offer_requires_buyer AFTER INSERT OR UPDATE ON offer
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION tre.check_minimum_participants('offer','offer_id');
CREATE CONSTRAINT TRIGGER buyer_change_preserves_minimum AFTER INSERT OR UPDATE OR DELETE ON offer_buyer
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION tre.check_minimum_participants('offer','offer_id');

CREATE FUNCTION tre.check_booking_capacity() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE old_id bigint; new_id bigint; session_id bigint;
BEGIN
    IF TG_OP <> 'INSERT' THEN old_id := OLD.showing_id; END IF;
    IF TG_OP <> 'DELETE' THEN new_id := NEW.showing_id; END IF;
    FOR session_id IN SELECT DISTINCT v FROM unnest(ARRAY[old_id,new_id]) v WHERE v IS NOT NULL LOOP
        IF (SELECT count(*) FROM tre.showing_booking WHERE showing_id = session_id
            AND status IN ('PENDING','CONFIRMED')) > 3 THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = format('BR09: showing %s exceeds three active party bookings',session_id);
        END IF;
    END LOOP;
    RETURN NULL;
END $$;

CREATE CONSTRAINT TRIGGER showing_capacity AFTER INSERT OR UPDATE OR DELETE ON showing_booking
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION tre.check_booking_capacity();

CREATE FUNCTION tre.guard_showing_time() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE old_property bigint; new_property bigint; old_agent bigint; id_to_lock bigint;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
        old_agent := OLD.agent_id;
        -- Protect the mapping LISTING -> PROPERTY against concurrent reassignment.
        PERFORM 1 FROM tre.listing WHERE listing_id IN (OLD.listing_id,NEW.listing_id)
            ORDER BY listing_id FOR SHARE;
        SELECT property_id INTO old_property FROM tre.listing WHERE listing_id = OLD.listing_id;
    ELSE
        PERFORM 1 FROM tre.listing WHERE listing_id = NEW.listing_id FOR SHARE;
    END IF;
    SELECT property_id INTO new_property FROM tre.listing WHERE listing_id = NEW.listing_id;
    FOR id_to_lock IN SELECT DISTINCT v FROM unnest(ARRAY[old_property,new_property]) v WHERE v IS NOT NULL ORDER BY v LOOP
        UPDATE tre.property SET property_ref = property_ref WHERE property_id = id_to_lock;
    END LOOP;
    FOR id_to_lock IN SELECT DISTINCT v FROM unnest(ARRAY[old_agent,NEW.agent_id]) v WHERE v IS NOT NULL ORDER BY v LOOP
        UPDATE tre.agent SET is_active = is_active WHERE agent_id = id_to_lock;
    END LOOP;
    -- Row CHECKs / FKs report invalid ranges or missing parents themselves.
    IF NEW.status = 'CANCELLED' OR new_property IS NULL OR NEW.ends_at <= NEW.starts_at
        OR NOT isfinite(NEW.starts_at) OR NOT isfinite(NEW.ends_at) THEN RETURN NEW; END IF;
    IF EXISTS (
        SELECT 1 FROM tre.showing s JOIN tre.listing l ON l.listing_id = s.listing_id
        WHERE s.showing_id <> NEW.showing_id AND s.status <> 'CANCELLED'
          AND (s.agent_id = NEW.agent_id OR l.property_id = new_property)
          AND s.starts_at < NEW.ends_at AND NEW.starts_at < s.ends_at
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR07: showing overlaps another session for the property or agent';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER c_guard_showing_time BEFORE INSERT OR UPDATE ON showing
    FOR EACH ROW EXECUTE FUNCTION tre.guard_showing_time();

-- Changing a listing's property must not bypass the cross-listing overlap rule.
CREATE FUNCTION tre.guard_listing_property_change() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE id_to_lock bigint;
BEGIN
    IF NEW.property_id IS NOT DISTINCT FROM OLD.property_id THEN RETURN NEW; END IF;
    FOR id_to_lock IN SELECT DISTINCT v FROM unnest(ARRAY[OLD.property_id,NEW.property_id]) v ORDER BY v LOOP
        UPDATE tre.property SET property_ref = property_ref WHERE property_id = id_to_lock;
    END LOOP;
    IF EXISTS (
        SELECT 1 FROM tre.showing moved JOIN tre.showing other
          ON moved.starts_at < other.ends_at AND other.starts_at < moved.ends_at
        JOIN tre.listing other_l ON other_l.listing_id = other.listing_id
        WHERE moved.listing_id = OLD.listing_id AND other.listing_id <> OLD.listing_id
          AND moved.status <> 'CANCELLED' AND other.status <> 'CANCELLED'
          AND other_l.property_id = NEW.property_id
    ) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR07: property reassignment would create overlapping showings';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER c_guard_listing_property BEFORE UPDATE ON listing
    FOR EACH ROW EXECUTE FUNCTION tre.guard_listing_property_change();

CREATE FUNCTION tre.guard_sale() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
DECLARE o tre.offer%ROWTYPE; person tre.staff%ROWTYPE; old_offer bigint; id_to_lock bigint;
BEGIN
    IF TG_OP = 'UPDATE' THEN old_offer := OLD.offer_id; END IF;
    FOR id_to_lock IN SELECT DISTINCT v FROM unnest(ARRAY[old_offer,NEW.offer_id]) v WHERE v IS NOT NULL ORDER BY v LOOP
        UPDATE tre.offer SET status = status WHERE offer_id = id_to_lock;
    END LOOP;
    SELECT * INTO o FROM tre.offer WHERE offer_id = NEW.offer_id;
    IF FOUND THEN
        IF o.status <> 'ACCEPTED' THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR14: a completed sale requires an ACCEPTED offer';
        END IF;
        IF NEW.completed_on < (o.accepted_at AT TIME ZONE 'America/Edmonton')::date THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR15: completion precedes Calgary-local acceptance date';
        END IF;
    END IF;
    -- Eligibility is checked at assignment time; later retirement/role changes
    -- do not erase or invalidate an already recorded historical sale.
    IF TG_OP = 'INSERT' OR NEW.coordinator_staff_id IS DISTINCT FROM OLD.coordinator_staff_id THEN
        UPDATE tre.staff SET is_active = is_active WHERE staff_id = NEW.coordinator_staff_id;
        SELECT * INTO person FROM tre.staff WHERE staff_id = NEW.coordinator_staff_id;
        IF FOUND AND (NOT person.is_active OR person.role_code <> 'COORDINATOR') THEN
            RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR16: assign an active COORDINATOR to the sale';
        END IF;
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER c_guard_sale BEFORE INSERT OR UPDATE ON sale_transaction
    FOR EACH ROW EXECUTE FUNCTION tre.guard_sale();

CREATE FUNCTION tre.guard_sold_offer() RETURNS trigger LANGUAGE plpgsql
SET search_path = pg_catalog, tre AS $$
BEGIN
    IF NEW IS NOT DISTINCT FROM OLD THEN RETURN NEW; END IF;
    IF EXISTS (SELECT 1 FROM tre.sale_transaction s WHERE s.offer_id = OLD.offer_id
        AND (NEW.status <> 'ACCEPTED' OR NEW.accepted_at IS NULL OR
            s.completed_on < (NEW.accepted_at AT TIME ZONE 'America/Edmonton')::date)) THEN
        RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = 'BR13-BR15: offer update would invalidate its completed sale';
    END IF;
    RETURN NEW;
END $$;
CREATE TRIGGER c_guard_sold_offer BEFORE UPDATE ON offer
    FOR EACH ROW EXECUTE FUNCTION tre.guard_sold_offer();
COMMIT;
