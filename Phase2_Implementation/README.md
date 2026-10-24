# TotallyRealEstate Phase 2 Implementation

This project implements the Phase 1 real estate data model in PostgreSQL, adds
showing notes in Cloud Firestore, and maps a Listing object to PostgreSQL JSONB.
It includes source scripts, synthetic datasets, explained queries, actual results
and the implementation report.

## Required deliverables

| Requirement | Included work |
|---|---|
| PostgreSQL tables, types, keys, constraints and indexes | 11 business tables, 63 attributes and 14 foreign keys; scripts 01-03 |
| Sample data with a 100-300-row target for major entities | 2,408 synthetic rows, including 8 internal staff |
| At least 10 business queries | 12 queries with joins, subqueries, aggregations, business explanations and complete JSON results |
| Views, triggers, procedures and transactions | 3 views, business-rule triggers, 2 procedures and 5 workflow demonstrations |
| Firestore document datastore | 60 showing notes, nested maps/arrays, CRUD and query evidence |
| Object-oriented entity and JSONB | Listing composition, 250 snapshots and 4 nested-data queries |
| Implementation report | English Word report |
| Narrated video | Recorded MP4 demonstration; see the link below |
| GitHub and setup documentation | Course folder structure and module README files |

The video should show the schema and data, several explained SQL queries, a
Firestore CRUD operation and query, and the OO/JSONB example with a query.
Showing a procedure or trigger in the video is optional.

## File structure

```text
Phase2_Implementation/
  SQL_Scripts/
  Query_Portfolio/
  NoSQL_Prototype/
  OO_JSONB_Mapping/
  Implementation_Report/
    Phase 2 documentation.docx
  Video/
    Video demonstaration.mp4
  README.md
```

## PostgreSQL setup

Use PostgreSQL 18 with pgAdmin Query Tool or psql. The recorded implementation
used PostgreSQL 18.6. Create a new empty database, such as tre_phase2.

Run these complete files in order:

1. [01_schema.sql](SQL_Scripts/01_schema.sql): create tables, keys and row constraints.
2. [02_indexes.sql](SQL_Scripts/02_indexes.sql): create supporting and conditional unique indexes.
3. [03_business_rules.sql](SQL_Scripts/03_business_rules.sql): install cross-row/table rule triggers.
4. [04_sample_data.sql](SQL_Scripts/04_sample_data.sql): load the synthetic fixture.
5. [05_verify.sql](SQL_Scripts/05_verify.sql): check structure, counts and rules.
6. [07_views.sql](SQL_Scripts/07_views.sql): create reporting views.
7. [08_stored_procedures.sql](SQL_Scripts/08_stored_procedures.sql): create workflow procedures.

[06_rule_tests.sql](SQL_Scripts/06_rule_tests.sql) is an optional development test;
its business-row changes roll back. Sequence gaps after rollback are normal.
The seed requires all eleven business tables to be empty and rejects a repeated
load. Use a new database when rebuilding the original fixture.

For psql, [run_all.sql](SQL_Scripts/run_all.sql) executes scripts 01-05. From the
project directory containing Phase2_Implementation:

```powershell
psql -X -h localhost -U postgres -d tre_phase2 -v ON_ERROR_STOP=1 -f './Phase2_Implementation/SQL_Scripts/run_all.sql'
```

Then execute 07 and 08. The runner contains psql commands; in pgAdmin, open and
execute the individual ordinary SQL files instead. After a failed manual
transaction, run ROLLBACK before correcting and retrying the file.

## Dataset

| Business table | Rows |
|---|---:|
| client | 300 |
| agent | 100 |
| staff | 8 |
| property | 200 |
| listing | 250 |
| listing_seller | 300 |
| showing | 300 |
| showing_booking | 300 |
| offer | 250 |
| offer_buyer | 300 |
| sale_transaction | 100 |
| Total | 2,408 |

SQL generates these rows deterministically with fixed arrays, generate_series
and arithmetic. Names, addresses, contacts, prices and events are fictitious.
Emails use example.org and phone samples use 555-0100 through 555-0199.
Business query results use the fixed October 19, 2026 reference date.

## Query Portfolio

Run [Business_Queries.sql](Query_Portfolio/Business_Queries.sql), or highlight one
complete D0/Q01-Q12 section. [Portfolio_Report.md](Query_Portfolio/Portfolio_Report.md)
contains questions, SQL, explanations and result previews. Every full result row,
transaction transcript and recorded plan is in [Results.json](Query_Portfolio/Results.json).
[Transaction_Examples.sql](Query_Portfolio/Transaction_Examples.sql) contains T01-T05.
Select one example. Its opening guard prevents accidental execution of the whole
file. T01 commits and must use a disposable database copy; T02-T05 restore business rows.

## Firestore

Project ID: totallyrealestate-phase-2. The default database uses Toronto
(northamerica-northeast2) and the Spark plan. Collection tre_phase2_showing_notes
contains 60 synthetic notes, three for each of 20 completed SQL showings.
Maps and arrays hold feedback, follow-up details, tags, features and concerns.

See [the NoSQL instructions](NoSQL_Prototype/README.md) for dependencies, local
seeding, CRUD, queries and explicit cloud validation commands. Node 24.12+ and
Java 21+ are required for the local emulator workflow. Install pinned packages
with npm ci; installed dependencies are not part of this archive.

## OO and JSONB

See [the mapping instructions](OO_JSONB_Mapping/README.md) for the Listing classes,
composition diagram and tradeoffs. Run OO_JSONB_Mapping/00_schema.sql, followed by
01_load_snapshots.sql, then the J01-J04 sections in JSONB_Queries.sql. Alternatively use the Python
exporter described in that module's README. It uses the Python standard library
and psql to reconstruct 250 Listing objects from the relational fixture.

## Data ownership

| Store | Responsibility |
|---|---|
| PostgreSQL tre | Authoritative operational identities, relationships, schedules, prices and statuses |
| Cloud Firestore | Showing-note text, tags and feedback, linked through exported SQL IDs |
| PostgreSQL tre_oo | Derived Listing snapshots refreshed explicitly from tre |

JSONB snapshots can become stale after relational edits. Firestore references
are checked against an exported SQL capture; there is no cross-store foreign key
or automatic distributed transaction.

## Credentials

Supply your own PostgreSQL host, port and role. Use the password prompt or a
local PGPASSFILE. Cloud operations use the official Firebase CLI OAuth login;
the emulator needs no cloud credentials. Keep secrets outside the repository.
NoSQL_Prototype/.gitignore excludes node_modules, local environment files,
Firebase temporary files and service-account keys.

## Report and hand-in

[Phase 2 documentation (Word)](Implementation_Report/Phase%202%20documentation.docx)

Brightspace requires one Word/PDF report, the narrated video or private YouTube
link, and the GitHub repository link. The report and recorded demonstration are
included in this repository. Brightspace submission must be completed separately.
Team repository:
https://github.com/SethG1262/Advanced_DataBase

## Demo video

[Watch or download the demonstration (MP4)](Video/Video%20demonstaration.mp4)
