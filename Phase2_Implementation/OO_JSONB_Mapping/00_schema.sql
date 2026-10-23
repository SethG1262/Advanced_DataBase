-- Separate read-model schema; the original tre schema keeps 11 tables/63 fields.
BEGIN;
CREATE SCHEMA tre_oo;
CREATE TABLE tre_oo.listing_snapshot (
    listing_id bigint PRIMARY KEY REFERENCES tre.listing(listing_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    schema_version integer NOT NULL DEFAULT 1 CHECK (schema_version = 1),
    captured_at timestamptz NOT NULL CHECK (isfinite(captured_at)),
    payload jsonb NOT NULL,
    CONSTRAINT snapshot_root_object CHECK (jsonb_typeof(payload)='object'),
    CONSTRAINT snapshot_required_fields CHECK (payload ?& ARRAY[
        'schema_version','listing_id','status','asking_price','property','agent','sellers','offers']),
    CONSTRAINT snapshot_matching_id CHECK (payload->>'listing_id' IS NOT NULL AND (payload->>'listing_id')::bigint = listing_id),
    CONSTRAINT snapshot_version CHECK (payload->>'schema_version' IS NOT NULL AND (payload->>'schema_version')::integer = schema_version),
    CONSTRAINT snapshot_nested_shapes CHECK (
        jsonb_typeof(payload->'property')='object' AND
        jsonb_typeof(payload->'agent')='object' AND
        jsonb_typeof(payload->'asking_price')='object' AND
        jsonb_typeof(payload->'sellers')='array' AND
        jsonb_typeof(payload->'offers')='array')
);
CREATE INDEX listing_snapshot_payload_gin ON tre_oo.listing_snapshot USING gin(payload jsonb_path_ops);
COMMENT ON TABLE tre_oo.listing_snapshot IS 'Derived Listing object snapshots. Refresh from tre; never use as a second authoritative operational store.';
COMMIT;
