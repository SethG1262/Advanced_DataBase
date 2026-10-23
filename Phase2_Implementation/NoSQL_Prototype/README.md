# Cloud Firestore showing notes

[Open the live database](https://console.firebase.google.com/project/totallyrealestate-phase-2/firestore/databases/-default-/data?hl=en)

Project totallyrealestate-phase-2 uses the default Firestore database in Toronto
(northamerica-northeast2). Collection tre_phase2_showing_notes contains 60
synthetic notes linked to 20 completed PostgreSQL showings. feedback and follow_up
are maps; tags, liked_features and concerns are arrays. ISO strings in the JSON
fixture become native Firestore timestamps during import.

## Files

| File | Purpose |
|---|---|
| firestore_demo.mjs | Dataset validation, seed, CRUD, F01-F03 queries and local/cloud runners |
| sample_data.json | The 60 notes and the captured PostgreSQL ID/time references |
| results/validation_results.json | All recorded local and cloud summaries, CRUD events, query rows and cloud metadata |
| results/data.png and results/indexes_ready.png | English console screenshots |
| firebase.json, firestore.rules, firestore.indexes.json | Emulator configuration, security rules and two composite indexes |
| package.json and package-lock.json | Commands and pinned Node dependencies |

## Local run

Use Node.js 24.12+ and Java 21+. From this directory:

```powershell
npm ci
npm run check:data
npm run validate:emulator
```

The runner starts a fresh loopback emulator, validates the fixture and repeated
seed, demonstrates CRUD on a separate temporary note, runs queries, checks that
anonymous client reads/writes are denied, and stops the emulator. Results update
the local section of results/validation_results.json. No cloud login is needed.
The cloud section preserves the separately recorded cloud evidence.

## Cloud reproduction

Use an authorized account and this explicit project ID:

```powershell
node node_modules/firebase-tools/lib/bin/firebase.js login
node node_modules/firebase-tools/lib/bin/firebase.js deploy --only firestore:rules,firestore:indexes --project totallyrealestate-phase-2
node firestore_demo.mjs --cloud --project totallyrealestate-phase-2 --write
```

Cloud mode reuses the official CLI OAuth login and keeps its access token in
memory. It rejects other project IDs and conflicting fixtures. It verifies both
indexes READY, compares all 60 documents, performs CRUD on its own temporary note,
and verifies F01=3, F02=20 and F03=60. Client Security Rules deny direct client
access; the authorized server uses separate IAM access. No credentials are included.

## Queries and data ownership

- F01: showing_id == 1, created_at descending; 3 notes.
- F02: follow_up.required == true, created_at ascending; 20 notes.
- F03: total document count; 60 notes.

Find these in the QUERIES F01 F02 F03 section of firestore_demo.mjs. For the video,
use the Firebase Console query builder and a numeric showing_id value. Updating
follow_up.status from PENDING to DONE and restoring PENDING demonstrates UPDATE.

PostgreSQL owns operational IDs, money and business states. Firestore owns note
content and feedback. After changing the SQL fixture, refresh its reference
capture with the OO exporter and run node firestore_demo.mjs --export-data before
validating a fresh emulator. There is no cross-store foreign key or automatic
distributed transaction.
