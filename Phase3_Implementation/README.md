# TotallyRealEstate Phase 3

This package extends the existing Phase 2 PostgreSQL model with class-table inheritance, nested JSONB features, real 384-dimensional embeddings, full-text/vector hybrid search, and a combined property search. The corpus contains **2,500 fictional topic documents linked to 250 listings and 200 properties**. One document is one listing/topic pair; it is not an additional property.

The current Brightspace instructions were read on November 17, 2026: [Phase 3 brief](https://learn.sait.ca/d2l/lms/dropbox/user/folder_submit_files.d2l?db=1062432&grpid=910505&isprv=0&bp=0&ou=886971). The page shows November 18, 2026 at 11:59 PM as the deadline. Its lower rubric still uses the older Big Data Integration title; this implementation follows the explicit OO, JSONB and vector tasks in the current instructions.

## Contents

| Folder | Contents |
|---|---|
| [Design_Plan](Design_Plan/) | Link to the design plan in the final combined Word document, plus the requirement-to-evidence checklist |
| [Diagrams](Diagrams/) | UML and data pipeline diagrams in PNG, SVG, draw.io and Mermaid formats |
| [SQL_Scripts](SQL_Scripts/) | Self-contained Phase 2 baseline, Phase 3 schema, data/vector loaders, indexes and executed query examples |
| [Embeddings](Embeddings/) | Raw JSONL, vectors, model manifest, predeclared relevance labels, Python pipeline and pinned dependencies |
| [Query_Results](Query_Results/) | Full CSV results, JSON/TXT execution plans, data audit, timings, integration tests and clean rebuild evidence |
| [Technical_Report](Technical_Report/) | Final combined Word technical report, design plan and contribution table |

The final document is [Phase 3 Technical Report and Design Plan](Technical_Report/Phase%203%20Technical%20Report%20and%20Design%20Plan.docx). Its **Design Plan** section is the submitted design plan. See [Design_Plan/README.md](Design_Plan/README.md) for the section outline.

This package is located at `Phase3_Implementation/` in the repository. Run the relative paths below from this package directory.

## Environment

Recorded execution used Windows, PostgreSQL 18.6, pgvector 0.8.7, Python 3.12, psql 18.6 and psycopg 3.3.9. The free model is `sentence-transformers/all-MiniLM-L6-v2`, with model revision, package versions and file hashes recorded in [model_manifest.json](Embeddings/model_manifest.json). Vectors have 384 dimensions, use mean pooling and are normalized. Both documents and queries use this same model on a local CPU with four PyTorch threads. No paid embedding service or API key is used.

The PostgreSQL server must have pgvector installed before `CREATE EXTENSION vector` can succeed. Official installation options, including Windows and Docker, are documented by [pgvector](https://github.com/pgvector/pgvector). For the recorded local environment the extension files were already installed. Use a role that may create the extension, schemas and functions in a **new development database**.

## Credentials

Supply standard libpq environment variables. Do not put credentials in SQL, code, the README or Git history. Use a local `PGPASSFILE` outside this folder, an OS-managed connection service or your normal interactive password prompt. `.gitignore` excludes local credential files and `.env` files. The delivered files do not contain the password used for testing.

PowerShell example, replacing the non-secret placeholders with your own settings:

```powershell
$env:PGHOST = '127.0.0.1'
$env:PGPORT = '5432'
$env:PGUSER = 'your_database_role'
$env:PGDATABASE = 'tre_phase3_demo'
$env:PGPASSFILE = 'C:\private\pgpass.conf'
createdb $env:PGDATABASE
```

## Fast SQL setup with supplied vectors

From this folder, run:

```powershell
psql -X -v ON_ERROR_STOP=1 -f SQL_Scripts/run_all.psql
```

The runner executes the original SQL files separately. In pgAdmin, open each complete file in Query Tool and execute it in this order; all files use the same new database. Wait for successful completion before continuing.

| Step | File under SQL_Scripts | Purpose |
| --- | --- | --- |
| 1 | `phase2_baseline/01_schema.sql` | Create the original 11 business tables and constraints |
| 2 | `phase2_baseline/02_indexes.sql` | Create Phase 2 query and conditional-uniqueness indexes |
| 3 | `phase2_baseline/03_business_rules.sql` | Install business-rule functions and triggers |
| 4 | `phase2_baseline/04_sample_data.sql` | Load 2,408 synthetic business records |
| 5 | `phase2_baseline/05_verify.sql` | Check Phase 2 structure, row counts and business rules |
| 6 | `phase2_baseline/07_views.sql` | Create the three reusable business views |
| 7 | `phase2_baseline/08_stored_procedures.sql` | Create the offer-acceptance and sale-completion procedures |
| 8 | `01_phase3_schema.sql` | Enable pgvector and create subtypes, JSONB features and document structures |
| 9 | `02_subtypes_and_features.sql` | Load 200 subtype rows, 200 feature records and six amenities |
| 10 | `03_load_documents.sql` | Load 2,500 source text records |
| 11 | `04_load_vectors.sql` | Load the supplied 384-dimensional vectors and their provenance |
| 12 | `05_indexes.sql` | Build JSONB GIN, HNSW and full-text GIN indexes and update statistics |

`run_all.psql` uses psql include commands and is not a pgAdmin SQL file. The baseline is self-contained and does not require Firestore or the old `tre_oo` snapshot schema.

The sequence above uses the supplied vectors. In a full regeneration, `generate_data.py` first creates the text and audit files after the Phase 2 baseline, then `embed.py` runs **after step 10 and before step 11**. It reads `raw_documents.jsonl`, encodes each title and body, and writes a fresh `04_load_vectors.sql`; step 11 then loads those new vectors. The bonus pipeline below performs this sequence automatically. `evaluate.py` and `validate.py` evaluate and check the data; they do not regenerate embeddings.

Run `06_oo_jsonb_examples.sql`, `07_vector_search_examples.sql`, `C1_filtered.sql` and `D1_combined.sql` to inspect outputs. The JSON update example rolls back. A repeated full setup fails rather than resetting an existing schema.

## Reproduce the results

```powershell
py -3.12 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r Embeddings/requirements-lock.txt
.\.venv\Scripts\python.exe Embeddings/evaluate.py
.\.venv\Scripts\python.exe Embeddings/validate.py
```

To regenerate the dataset, embeddings, SQL loads and evaluations for the bonus, select a **different new empty database** and run:

```powershell
createdb $env:PGDATABASE
.\.venv\Scripts\python.exe Embeddings/run_pipeline.py --regenerate
```

The first model download needs Internet access. The manifest pins the model revision; later runs use the local Hugging Face cache. The pipeline checks that `tre` and `tre_p3` do not already exist. It never drops a database. It writes fresh execution results over the result files in this working copy; save a copy first if you want to retain an earlier run. Without `--regenerate`, the pipeline loads the supplied text/vector SQL and reruns evaluation and tests.

The manifest records the input as `title + newline + body`. The tokenizer audit includes special tokens. Observed lengths were 72-94 tokens against a 256-token model limit, so no text needed truncation. All 2,500 vectors are checked for dimensions, finite values, normalization and agreement with the NumPy file.

The final review passed 35 integration checks, including decimal JSON number handling and bigint range limits. A separate ZIP extraction regenerated the vectors and matched all 18 table fingerprints; it also checked all 12,500 relevance labels and ran the four SQL example files in separate psql sessions. See [second_review.json](Query_Results/second_review.json) and [review_changes.md](Query_Results/review_changes.md).

## Design and authority

`tre.property` keeps identity and common property fields. Four `tre_p3` subtype tables hold class-specific fields. Deferred database rules require exactly one subtype matching `property_type`. `property_catalog` and `property_summary()` return different summaries for each subclass. `set_fenced_yard()` is an encapsulated operation; constraints and triggers also protect direct writes. The prototype uses invoker privileges and does not claim that the schema owner is prevented from direct table access.

`property_features.features` is the authoritative store for optional feature facts. Its required structure is checked, nested boolean types are validated, amenity IDs must exist, and the small amenity catalogue is immutable in this prototype. Fixed identity, money, room counts, property types and business status stay relational. Phase 2 property/listing columns are not removed or moved.

`listing_document.title/body` are the stored search source. Raw JSONL is the reproducible input snapshot. Embeddings and full-text vectors are derived. A text edit recomputes its hash and clears its embedding provenance, requiring re-embedding. Permanent feature edits do not automatically rewrite historical topic documents; this fixture uses a fixed captured dataset, and the update demonstration rolls back. A production application would need an explicit text refresh and re-embedding workflow.

## Evaluation and performance

Five natural-language searches have complete top-five outputs in `S1_top5.csv` through `S5_top5.csv`. `qrels.csv` was generated before retrieval from declared topic and positive-feature rules. These are assistant-authored synthetic relevance labels, not independent human assessments. The report lists all 25 returned document IDs and relevance labels. Text templates and query similarity make this a small, easy benchmark; its scores do not establish real-world retrieval quality.

The hybrid search combines an English full-text phrase search for `Juniper Station` with vector ranking, using reciprocal rank fusion with k=60 and top-100 candidate lists. It is compared against vector-only search, including cases where it makes no measurable precision improvement.

HNSW uses `m=16`, `ef_construction=64`, cosine operator class and query-time `ef_search=200`. A tuning probe showed that 40/100 could miss the target semantic cluster after a rebuild; 200 recovered the expected top ten in that probe. `hnsw_tuning_probe.json` retains that evidence. Approximate index results can still change after rebuilding; compare against exact search on each deployment.

For the controlled top-ten comparison, exact search disables index/bitmap scans, and the HNSW path disables sequential scans. Settings apply only within rollback transactions. Seven timed repetitions follow one warm-up, with full TXT/JSON plans proving the paths used. Normal filtered search and JSONB queries retain the planner's default choice. The GIN diagnostic disables sequential and ordinary index scans to demonstrate the available bitmap path; it is not presented as the default plan.

## Dataset source, licence and AI disclosure

All source records are fictional. The source is this project's `generate_data.py`, which reuses the synthetic Phase 2 keys and generates deterministic topic text from feature facts. No Kaggle dataset, scraped listing, real personal record or Calgary assessment file is used. There is no third-party dataset licence to cite, and no separate public redistribution licence is granted for this project-authored corpus. The model is distributed under Apache-2.0: [model card](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2).

OpenAI Codex assisted with design, SQL, Python, sentence templates, relevance rules, tests, diagrams and documentation, and executed the recorded local runs. Dataset generation itself calls no generative API. Team members should review the work and disclose assistance according to course policy. The final combined Word report records the team members and their task-specific contributions.

## Submission

Submit the [final combined technical report and design plan](Technical_Report/Phase%203%20Technical%20Report%20and%20Design%20Plan.docx) through Brightspace together with the [Phase 3 GitHub link](https://github.com/SethG1262/Advanced_DataBase/tree/main/Phase3_Implementation). The course permits the design plan to be part of the technical report. The document also contains the contribution table. The reproducible `Embeddings/run_pipeline.py` script provides the optional bonus workflow.

The dated records in `Query_Results` describe the execution and reviews performed when those records were created. Repository publication does not itself submit the assignment to Brightspace.

Technical references: [PostgreSQL JSONB](https://www.postgresql.org/docs/18/datatype-json.html), [PostgreSQL full text search](https://www.postgresql.org/docs/18/textsearch.html), [pgvector](https://github.com/pgvector/pgvector), [model card](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2).

[Return to the project overview](../README.md).
