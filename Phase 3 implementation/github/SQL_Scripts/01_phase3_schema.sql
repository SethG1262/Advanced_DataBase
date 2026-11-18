-- Run once after the supplied Phase 2 baseline, in a new development database.
BEGIN;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE SCHEMA tre_p3;

-- Class-table mapping. tre.property is the authoritative superclass.
CREATE TABLE tre_p3.detached_property (
 property_id bigint PRIMARY KEY REFERENCES tre.property ON DELETE RESTRICT,
 lot_area_sqm numeric(10,2) NOT NULL CHECK (lot_area_sqm > 0 AND lot_area_sqm < 'Infinity'::numeric)
);
CREATE TABLE tre_p3.condo_property (
 property_id bigint PRIMARY KEY REFERENCES tre.property ON DELETE RESTRICT,
 floor_number smallint NOT NULL CHECK (floor_number >= 0),
 monthly_condo_fee numeric(10,2) NOT NULL CHECK (monthly_condo_fee >= 0 AND monthly_condo_fee < 'Infinity'::numeric)
);
CREATE TABLE tre_p3.townhouse_property (
 property_id bigint PRIMARY KEY REFERENCES tre.property ON DELETE RESTRICT,
 shared_walls smallint NOT NULL CHECK (shared_walls BETWEEN 1 AND 2)
);
CREATE TABLE tre_p3.other_property (
 property_id bigint PRIMARY KEY REFERENCES tre.property ON DELETE RESTRICT,
 category_note text NOT NULL CHECK (length(btrim(category_note)) > 0)
);

CREATE FUNCTION tre_p3.check_subtype() RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog,tre_p3 AS $$
DECLARE k bigint; typ text; n int; matching boolean;
BEGIN
 k := CASE WHEN TG_OP='DELETE' THEN OLD.property_id ELSE NEW.property_id END;
 SELECT property_type INTO typ FROM tre.property WHERE property_id=k FOR UPDATE;
 IF NOT FOUND THEN RETURN NULL; END IF;
 SELECT (EXISTS(SELECT 1 FROM tre_p3.detached_property WHERE property_id=k))::int
      + (EXISTS(SELECT 1 FROM tre_p3.condo_property WHERE property_id=k))::int
      + (EXISTS(SELECT 1 FROM tre_p3.townhouse_property WHERE property_id=k))::int
      + (EXISTS(SELECT 1 FROM tre_p3.other_property WHERE property_id=k))::int INTO n;
 matching := CASE typ
  WHEN 'DETACHED' THEN EXISTS(SELECT 1 FROM tre_p3.detached_property WHERE property_id=k)
  WHEN 'CONDO' THEN EXISTS(SELECT 1 FROM tre_p3.condo_property WHERE property_id=k)
  WHEN 'TOWNHOUSE' THEN EXISTS(SELECT 1 FROM tre_p3.townhouse_property WHERE property_id=k)
  WHEN 'OTHER' THEN EXISTS(SELECT 1 FROM tre_p3.other_property WHERE property_id=k) END;
 IF n<>1 OR NOT matching THEN RAISE EXCEPTION 'Property % must have exactly one matching subtype',k USING ERRCODE='23514'; END IF;
 RETURN NULL;
END $$;
CREATE FUNCTION tre_p3.lock_subtype_parent() RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog,tre_p3 AS $$
BEGIN
 IF TG_OP='UPDATE' AND NEW.property_id<>OLD.property_id THEN
  RAISE EXCEPTION 'Subtype identity cannot change' USING ERRCODE='23514';
 END IF;
 -- Serialize subtype writes and create a row version for repeatable-read safety.
 UPDATE tre.property SET property_type=property_type
 WHERE property_id=CASE WHEN TG_OP='DELETE' THEN OLD.property_id ELSE NEW.property_id END;
 RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['detached_property','condo_property','townhouse_property','other_property'] LOOP
  EXECUTE format('CREATE TRIGGER subtype_lock BEFORE INSERT OR UPDATE OR DELETE ON tre_p3.%I FOR EACH ROW EXECUTE FUNCTION tre_p3.lock_subtype_parent()',t);
  EXECUTE format('CREATE CONSTRAINT TRIGGER subtype_complete AFTER INSERT OR UPDATE OR DELETE ON tre_p3.%I DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION tre_p3.check_subtype()',t);
 END LOOP;
END $$;
CREATE CONSTRAINT TRIGGER phase3_subtype_complete AFTER INSERT OR UPDATE ON tre.property
DEFERRABLE INITIALLY DEFERRED FOR EACH ROW EXECUTE FUNCTION tre_p3.check_subtype();

CREATE TABLE tre_p3.amenity (
 amenity_id bigint PRIMARY KEY, name text NOT NULL, kind text NOT NULL
);
CREATE FUNCTION tre_p3.valid_features(j jsonb) RETURNS boolean LANGUAGE plpgsql IMMUTABLE
SET search_path=pg_catalog AS $$
DECLARE a jsonb;
BEGIN
 IF jsonb_typeof(j) IS DISTINCT FROM 'object' OR
 NOT (j ?& ARRAY['schema_version','accessibility','outdoor','nearby_amenities']) THEN RETURN false; END IF;
 IF j->'schema_version' IS DISTINCT FROM '1'::jsonb OR
 jsonb_typeof(j->'accessibility') IS DISTINCT FROM 'object' OR
 jsonb_typeof(j#>'{accessibility,step_free}') IS DISTINCT FROM 'boolean' OR
 jsonb_typeof(j->'outdoor') IS DISTINCT FROM 'object' OR
 jsonb_typeof(j#>'{outdoor,fenced_yard}') IS DISTINCT FROM 'boolean' OR
 jsonb_typeof(j->'nearby_amenities') IS DISTINCT FROM 'array' THEN RETURN false; END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(j->'nearby_amenities') LOOP
  IF jsonb_typeof(a) IS DISTINCT FROM 'object' OR
  jsonb_typeof(a->'amenity_id') IS DISTINCT FROM 'number' OR
  jsonb_typeof(a->'distance_m') IS DISTINCT FROM 'number' THEN RETURN false; END IF;
  IF (a->>'amenity_id')::numeric<=0 OR (a->>'amenity_id')::numeric>9223372036854775807
  OR (a->>'amenity_id')::numeric<>trunc((a->>'amenity_id')::numeric)
  OR (a->>'distance_m')::numeric<0 THEN RETURN false; END IF;
 END LOOP;
 RETURN true;
END $$;
CREATE TABLE tre_p3.property_features (
 property_id bigint PRIMARY KEY REFERENCES tre.property ON DELETE RESTRICT,
 features jsonb NOT NULL CHECK (tre_p3.valid_features(features) IS TRUE)
);
CREATE FUNCTION tre_p3.check_amenities() RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog,tre_p3 AS $$
DECLARE a jsonb;
BEGIN
 IF NOT tre_p3.valid_features(NEW.features) THEN RAISE EXCEPTION 'Invalid features JSON' USING ERRCODE='23514'; END IF;
 FOR a IN SELECT value FROM jsonb_array_elements(NEW.features->'nearby_amenities') LOOP
  PERFORM 1 FROM tre_p3.amenity WHERE amenity_id=(a->>'amenity_id')::numeric::bigint FOR KEY SHARE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown amenity ID' USING ERRCODE='23503'; END IF;
 END LOOP;
 RETURN NEW;
END $$;
CREATE TRIGGER features_amenity_refs BEFORE INSERT OR UPDATE ON tre_p3.property_features
FOR EACH ROW EXECUTE FUNCTION tre_p3.check_amenities();
CREATE FUNCTION tre_p3.keep_amenity_catalog() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN RAISE EXCEPTION 'Amenity catalogue is immutable in this prototype' USING ERRCODE='23514'; END $$;
CREATE TRIGGER amenity_immutable BEFORE UPDATE OR DELETE ON tre_p3.amenity
FOR EACH ROW EXECUTE FUNCTION tre_p3.keep_amenity_catalog();

CREATE VIEW tre_p3.property_catalog AS
SELECT p.*, CASE p.property_type
 WHEN 'DETACHED' THEN 'Detached home; lot '||d.lot_area_sqm||' sqm'
 WHEN 'CONDO' THEN 'Condo; floor '||c.floor_number||'; monthly fee CAD '||c.monthly_condo_fee
 WHEN 'TOWNHOUSE' THEN 'Townhouse; shared walls '||t.shared_walls
 ELSE 'Other property; '||o.category_note END AS subclass_summary,
 f.features
FROM tre.property p
LEFT JOIN tre_p3.detached_property d USING(property_id)
LEFT JOIN tre_p3.condo_property c USING(property_id)
LEFT JOIN tre_p3.townhouse_property t USING(property_id)
LEFT JOIN tre_p3.other_property o USING(property_id)
LEFT JOIN tre_p3.property_features f USING(property_id);
CREATE FUNCTION tre_p3.property_summary(k bigint) RETURNS text LANGUAGE sql STABLE
SET search_path=pg_catalog,tre_p3 AS $$ SELECT subclass_summary FROM tre_p3.property_catalog WHERE property_id=k $$;
CREATE FUNCTION tre_p3.set_fenced_yard(k bigint, enabled boolean) RETURNS jsonb LANGUAGE plpgsql
SET search_path=pg_catalog,tre_p3 AS $$
DECLARE result jsonb;
BEGIN
 IF enabled IS NULL THEN RAISE EXCEPTION 'A boolean is required' USING ERRCODE='23514'; END IF;
 UPDATE tre_p3.property_features SET features=jsonb_set(features,'{outdoor,fenced_yard}',to_jsonb(enabled),false)
 WHERE property_id=k RETURNING features INTO result;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown property' USING ERRCODE='P0002'; END IF;
 RETURN result;
END $$;

CREATE TABLE tre_p3.listing_document (
 document_id bigint PRIMARY KEY,
 listing_id bigint NOT NULL REFERENCES tre.listing ON DELETE RESTRICT,
 topic text NOT NULL,
 title text NOT NULL,
 body text NOT NULL CHECK (length(btrim(body))>=40),
 source_text_sha256 char(64) NOT NULL,
 embedding public.vector(384),
 embedding_model text,
 embedding_revision text,
 embedded_text_sha256 char(64),
 search_terms tsvector GENERATED ALWAYS AS (to_tsvector('english',title||' '||body)) STORED,
 UNIQUE(listing_id,topic),
 CHECK ((embedding IS NULL AND embedded_text_sha256 IS NULL AND embedding_model IS NULL AND embedding_revision IS NULL)
 OR (embedding IS NOT NULL AND embedded_text_sha256 IS NOT NULL AND embedding_model IS NOT NULL
 AND embedding_revision IS NOT NULL AND embedded_text_sha256=source_text_sha256))
);
CREATE INDEX listing_document_listing_idx ON tre_p3.listing_document(listing_id);
COMMENT ON TABLE tre_p3.listing_document IS 'One synthetic topic document for a listing. Search evaluation is at document grain. Embeddings and tsvectors are derived.';
CREATE FUNCTION tre_p3.document_hash() RETURNS trigger LANGUAGE plpgsql
SET search_path=pg_catalog AS $$
BEGIN
 NEW.source_text_sha256:=encode(sha256(convert_to(NEW.title||E'\n'||NEW.body,'UTF8')),'hex');
 IF TG_OP='UPDATE' AND (NEW.title IS DISTINCT FROM OLD.title OR NEW.body IS DISTINCT FROM OLD.body) THEN
  NEW.embedding:=NULL; NEW.embedding_model:=NULL; NEW.embedding_revision:=NULL; NEW.embedded_text_sha256:=NULL;
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER document_text_hash BEFORE INSERT OR UPDATE ON tre_p3.listing_document
FOR EACH ROW EXECUTE FUNCTION tre_p3.document_hash();
COMMIT;
