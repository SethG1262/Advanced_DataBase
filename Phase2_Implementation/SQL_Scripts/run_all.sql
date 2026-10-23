-- psql only: from any directory, psql -X -v ON_ERROR_STOP=1 -d tre_phase2 -f /path/to/run_all.sql
-- pgAdmin: execute 01 through 05 separately in the same chosen database.
\set ON_ERROR_STOP on
\ir 01_schema.sql
\ir 02_indexes.sql
\ir 03_business_rules.sql
\ir 04_sample_data.sql
\ir 05_verify.sql
