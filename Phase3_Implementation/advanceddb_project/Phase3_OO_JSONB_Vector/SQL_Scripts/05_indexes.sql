-- Build after loading all documents and embeddings.
CREATE INDEX property_features_gin ON tre_p3.property_features USING gin(features jsonb_path_ops);
CREATE INDEX listing_document_hnsw ON tre_p3.listing_document USING hnsw(embedding public.vector_cosine_ops)
WITH (m=16, ef_construction=64);
CREATE INDEX listing_document_fts ON tre_p3.listing_document USING gin(search_terms);
ANALYZE tre_p3.property_features;
ANALYZE tre_p3.listing_document;
