// Cloud mode requires an explicit project and --write. The default prints help.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { mkdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import path from 'node:path';
import os from 'node:os';
import { Firestore } from '@google-cloud/firestore';
import { initializeApp, deleteApp } from 'firebase/app';
import { getFirestore, connectFirestoreEmulator, doc, getDoc, setDoc, terminate } from 'firebase/firestore';

// DATA MODEL AND REFERENCE VALIDATION
const root = path.dirname(fileURLToPath(import.meta.url));
const collectionName = 'tre_phase2_showing_notes';
const projectId = 'demo-tre-phase2';
const sampleData = JSON.parse(await readFile(path.join(root, 'sample_data.json'), 'utf8'));
const references = sampleData.postgres_references;
const knownReferences = new Set(references.showings.map(s => `${s.showing_id}|${s.listing_id}|${s.agent_id}`));

function normalize(value) {
  if (value instanceof Date) return value.toISOString();
  if (value && typeof value.toDate === 'function') return value.toDate().toISOString();
  if (Array.isArray(value)) return value.map(normalize);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(k => [k, normalize(value[k])]));
  return value;
}

function validateNote(data) {
  assert.equal(data.schema_version, 1);
  assert.equal(data.prototype_tag, 'tre-phase2-v1');
  assert(knownReferences.has(`${data.showing_id}|${data.listing_id}|${data.author_agent_id}`), 'Unknown/mismatched PostgreSQL reference');
  assert.equal(typeof data.note_text, 'string');
  assert(data.note_text.length >= 10);
  assert(Array.isArray(data.tags) && data.tags.length > 0 && data.tags.every(x => typeof x === 'string'));
  assert(data.feedback && !Array.isArray(data.feedback));
  assert(['HIGH', 'MEDIUM', 'LOW'].includes(data.feedback.interest_level));
  assert(Number.isInteger(data.feedback.score) && data.feedback.score >= 1 && data.feedback.score <= 5);
  assert(Array.isArray(data.feedback.liked_features) && Array.isArray(data.feedback.concerns));
  assert.equal(typeof data.follow_up?.required, 'boolean');
  assert(['PENDING', 'NOT_REQUIRED', 'DONE'].includes(data.follow_up.status));
  const created = new Date(normalize(data.created_at)), updated = new Date(normalize(data.updated_at));
  assert(Number.isFinite(created.getTime()) && Number.isFinite(updated.getTime()) && updated >= created);
  return data;
}

function buildDocuments() {
  assert.equal(references.showings.length, 20);
  return Array.from({ length: 60 }, (_, i) => {
    const source = references.showings[Math.floor(i / 3)];
    const created = new Date(new Date(source.ends_at).getTime() + (i % 3 + 1) * 15 * 60_000);
    const high = i % 3 === 0;
    const data = {
      schema_version: 1, prototype_tag: 'tre-phase2-v1',
      showing_id: source.showing_id, listing_id: source.listing_id, author_agent_id: source.agent_id,
      note_text: ['Initial agent summary of property features and questions.',
        'Follow-up review of layout preferences and maintenance concerns.',
        'Closing note summarizing the next conversation with the client.'][i % 3],
      tags: ['showing-feedback', ['initial-review', 'follow-up', 'summary'][i % 3]],
      feedback: { interest_level: ['HIGH', 'MEDIUM', 'LOW'][i % 3], score: 5 - i % 3,
        liked_features: [['layout', 'natural light'], ['location'], ['storage']][i % 3],
        concerns: i % 3 === 2 ? ['maintenance questions'] : [] },
      follow_up: { required: high, status: high ? 'PENDING' : 'NOT_REQUIRED' },
      created_at: created.toISOString(), updated_at: created.toISOString()
    };
    validateNote(data);
    return { id: `tre-phase2-note-${String(i + 1).padStart(4, '0')}`, data };
  });
}

async function saveJson(relative, value) {
  if (relative.endsWith('/exported_documents.json')) return;
  const match = /^results\/(cloud\/)?([^/]+)\.json$/.exec(relative);
  assert(match, 'Unknown result destination');
  const target = path.join(root, 'results/validation_results.json');
  let recorded;
  try { recorded = JSON.parse(await readFile(target, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw error; recorded = { local: {}, cloud: {} }; }
  recorded[match[1] ? 'cloud' : 'local'][match[2]] = normalize(value);
  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, JSON.stringify(recorded, null, 2) + '\n', 'utf8');
}

function toFirestore(data) {
  validateNote(data);
  return { ...data, created_at: new Date(data.created_at), updated_at: new Date(data.updated_at) };
}

// LOCAL CLIENT
function makeClient() {
  const endpoint = process.env.FIRESTORE_EMULATOR_HOST;
  if (!endpoint || !/^(127\.0\.0\.1|localhost):\d+$/.test(endpoint)) {
    throw new Error('Local-only prototype: start the Firestore Emulator on loopback first. Cloud writes are disabled.');
  }
  return new Firestore({ projectId });
}

// SEED
async function seed(db, documents) {
  const refs = documents.map(x => db.collection(collectionName).doc(x.id));
  const found = await db.getAll(...refs);
  if (found.some(x => x.exists)) {
    assert(found.every(x => x.exists), 'Refusing to overwrite a partially populated fixture');
    found.forEach((snapshot, i) => assert.deepEqual(normalize(snapshot.data()), normalize(documents[i].data), 'Existing fixture differs; no overwrite performed'));
    return { created: 0, unchanged: documents.length };
  }
  const batch = db.batch();
  documents.forEach((item, i) => batch.create(refs[i], toFirestore(item.data)));
  await batch.commit();
  return { created: documents.length, unchanged: 0 };
}

// QUERIES F01 F02 F03
async function runQueries(db) {
  const notes = db.collection(collectionName);
  // F01: equality filter combined with timestamp ordering.
  const byShowing = await notes.where('showing_id', '==', references.showings[0].showing_id)
    .orderBy('created_at', 'desc').get();
  // F02: nested-map filter combined with timestamp ordering.
  const followUp = await notes.where('follow_up.required', '==', true)
    .orderBy('created_at', 'asc').get();
  // F03: aggregate count, independent of downloading every document.
  const count = await notes.count().get();
  const rows = snapshot => snapshot.docs.map(d => ({ id: d.id, ...d.data() }));
  return { F01_notes_for_showing: rows(byShowing), F02_follow_up_required: rows(followUp),
    F03_total_count: count.data().count };
}

// CRUD EXAMPLE
async function demonstrateCrud(db, sample) {
  const ref = db.collection(collectionName).doc('tre-phase2-crud-example');
  assert(!(await ref.get()).exists, 'Temporary demo ID already exists; no overwrite/delete performed');
  let createdHere = false;
  const events = [];
  try {
    await ref.create(toFirestore(sample));
    createdHere = true;
    events.push({ operation: 'CREATE', document_id: ref.id, success: true });
    const before = await ref.get();
    validateNote(before.data());
    events.push({ operation: 'READ', document: normalize(before.data()) });
    await ref.update({ 'follow_up.status': 'DONE', 'feedback.score': 4,
      updated_at: new Date(new Date(sample.created_at).getTime() + 60_000) });
    const changed = await ref.get();
    assert.equal(changed.get('follow_up.status'), 'DONE');
    validateNote(changed.data());
    events.push({ operation: 'UPDATE', document: normalize(changed.data()) });
    await ref.delete({ lastUpdateTime: changed.updateTime });
    createdHere = false;
    assert(!(await ref.get()).exists);
    events.push({ operation: 'DELETE', document_id: ref.id, exists_after_delete: false });
    return events;
  } finally {
    if (createdHere) {
      const current = await ref.get();
      if (current.exists) await ref.delete({ lastUpdateTime: current.updateTime });
    }
  }
}

// FULL LOCAL SDK AND RULES VALIDATION
async function validateLocal() {
const documents = buildDocuments();
assert.deepEqual(normalize(documents), normalize(sampleData.documents));
const db = makeClient();
try {
  const first = await seed(db, documents);
  const second = await seed(db, documents);
  assert.equal(second.unchanged, 60);
  const negativeCases = [
    x => { x.showing_id = 999999; }, x => { x.listing_id = 999999; },
    x => { x.author_agent_id = 999999; }, x => { x.tags = 'invalid'; },
    x => { x.feedback.interest_level = 'UNKNOWN'; },
    x => { x.follow_up.required = 'yes'; }, x => { x.created_at = 'invalid'; }
  ];
  for (const change of negativeCases) {
    const invalid = structuredClone(documents[0].data); change(invalid);
    assert.throws(() => validateNote(invalid));
  }
  const crud = await demonstrateCrud(db, documents[0].data);
  const queries = await runQueries(db);
  assert.equal(queries.F01_notes_for_showing.length, 3);
  assert.equal(queries.F02_follow_up_required.length, 20);
  assert.equal(queries.F03_total_count, 60);
  const all = await db.collection(collectionName).orderBy('__name__').get();
  assert.equal(all.size, 60);
  const exported = all.docs.map(d => ({ id: d.id, data: normalize(d.data()) }));
  assert.deepEqual(exported, normalize(documents));
  // The web/client SDK is anonymous and must be denied by firestore.rules.
  // The trusted server SDK above bypasses Rules; it does not prove cloud IAM.
  const app = initializeApp({ projectId, appId: 'tre-local-rules-check' }, 'tre-rules-check');
  const webDb = getFirestore(app);
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  connectFirestoreEmulator(webDb, host, Number(port));
  let denied = 0;
  try {
    for (const action of [() => getDoc(doc(webDb, collectionName, documents[0].id)),
      () => setDoc(doc(webDb, collectionName, 'anonymous-write-must-fail'), { invalid: true })]) {
      await assert.rejects(action, error => error.code === 'permission-denied');
      denied++;
    }
  } finally { await terminate(webDb); await deleteApp(app); }
  assert(!(await db.collection(collectionName).doc('anonymous-write-must-fail').get()).exists);
  await saveJson('results/crud_operations.json', crud);
  await saveJson('results/query_results.json', queries);
  await saveJson('results/exported_documents.json', exported);
  const packageInfo = JSON.parse(await readFile(path.join(root, 'package.json'), 'utf8'));
  const summary = {
    result: 'PASS', mode: 'LOCAL_FIRESTORE_EMULATOR_ONLY', actual_cloud_deployment: false,
    recorded_at_utc: new Date().toISOString(),
    project_id: projectId, endpoint: process.env.FIRESTORE_EMULATOR_HOST,
    collection: collectionName, documents: all.size, nested_maps: ['feedback', 'follow_up'],
    arrays: ['tags', 'feedback.liked_features', 'feedback.concerns'],
    first_seed: first, repeated_seed: second, crud_operations: ['CREATE', 'READ', 'UPDATE', 'DELETE'],
    query_row_counts: { F01: 3, F02: 20, F03: 60 }, rejected_invalid_notes: negativeCases.length,
    anonymous_client_operations_denied: denied, postgres_reference_validation: 'PASS',
    seed_documents_unchanged_after_crud: true, node_version: process.version,
    dependencies: packageInfo.dependencies, firebase_tools: packageInfo.devDependencies['firebase-tools'],
    cloud_indexes_verified: false, cloud_iam_verified: false,
    limitation: 'Emulator validates local SDK operations and Rules; it does not enforce production composite-index requirements or validate cloud deployment/IAM.'
  };
  await saveJson('results/summary.json', summary);
  console.log(JSON.stringify(summary, null, 2));
} finally { await db.terminate(); }

}

// EXPLICIT CLOUD CRUD AND QUERY VALIDATION
async function validateCloud() {
// Explicit cloud runner. The local emulator runner and client remain separate.
// Uses the existing official Firebase CLI OAuth login without exporting a key.
const args = process.argv.slice(2);
const project = args[args.indexOf('--project') + 1];
assert(args.includes('--project') && project === 'totallyrealestate-phase-2',
  'Supply --project totallyrealestate-phase-2 explicitly. Other projects are refused.');
assert(args.includes('--write'), 'This runner creates 60 synthetic notes and a temporary CRUD note. Supply --write explicitly.');
assert(!process.env.FIRESTORE_EMULATOR_HOST, 'Unset FIRESTORE_EMULATOR_HOST for a cloud run.');
const require = createRequire(import.meta.url);
const auth = require('firebase-tools/lib/auth');
const account = auth.getGlobalDefaultAccount();
assert(account?.tokens?.refresh_token, 'Log into the official Firebase CLI first.');
const token = (await auth.getAccessToken(account.tokens.refresh_token,
  ['https://www.googleapis.com/auth/cloud-platform'])).access_token;
assert(token, 'No OAuth access token available.');
const database = `projects/${project}/databases/(default)`;
const parent = database + '/documents';
const prefix = 'https://firestore.googleapis.com/v1/';
async function request(resource, body, options = {}) {
  const response = await fetch(prefix + resource, {
    method: options.method || (body ? 'POST' : 'GET'),
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    ...(body ? { body: JSON.stringify(body) } : {})
  });
  const result = await response.json();
  if (!response.ok) {
    const problem = result.error || (Array.isArray(result) && result.find(x=>x.error)?.error);
    throw new Error(`${response.status} ${resource}: ${problem?.message || 'Request failed'}`);
  }
  return result;
}
function encode(value, key = '') {
  if ((key === 'created_at' || key === 'updated_at') && typeof value === 'string')
    return { timestampValue: value };
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') return Number.isInteger(value)
    ? { integerValue: String(value) } : { doubleValue: value };
  if (Array.isArray(value)) return { arrayValue: { values: value.map(x => encode(x)) } };
  return { mapValue: { fields: fields(value) } };
}
const fields = value => Object.fromEntries(Object.entries(value).map(([k,v]) => [k,encode(v,k)]));
function decode(value) {
  if ('timestampValue' in value) return new Date(value.timestampValue).toISOString();
  if ('integerValue' in value) return Number(value.integerValue);
  if ('doubleValue' in value) return value.doubleValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('stringValue' in value) return value.stringValue;
  if ('arrayValue' in value) return (value.arrayValue.values || []).map(decode);
  if ('mapValue' in value) return Object.fromEntries(Object.entries(value.mapValue.fields || {}).map(([k,v])=>[k,decode(v)]));
  return null;
}
const decodeDoc = doc => ({ id: doc.name.split('/').at(-1),
  data: normalize(Object.fromEntries(Object.entries(doc.fields || {}).map(([k,v])=>[k,decode(v)]))) });
const name = id => `${parent}/${collectionName}/${id}`;
const documents = buildDocuments();
const dbInfo = await request(database);
assert.equal(dbInfo.locationId, 'northamerica-northeast2');
const expectedIndexes=JSON.parse(await readFile(path.join(root,'firestore.indexes.json'),'utf8')).indexes;
let indexes;
for(let attempt=0;attempt<21;attempt++) {
  indexes=await request(database+'/collectionGroups/'+collectionName+'/indexes');
  const actual=indexes.indexes || [];
  if(expectedIndexes.every(expected=>actual.some(index=>index.state==='READY' && index.queryScope===expected.queryScope &&
    expected.fields.every(field=>index.fields.some(x=>x.fieldPath===field.fieldPath && x.order===field.order))))) break;
  assert(attempt<20,'Cloud composite indexes did not become READY within 10 minutes');
  console.log(`Cloud indexes are building; checking again in 30 seconds (${attempt+1}/20).`);
  await new Promise(resolve=>setTimeout(resolve,30000));
}
const snapshots = await request(parent + ':batchGet', { documents: documents.map(x=>name(x.id)) });
const found = snapshots.filter(x=>x.found).map(x=>decodeDoc(x.found));
let seed;
if (found.length) {
  assert.equal(found.length,60,'Refusing to overwrite a partial existing fixture');
  assert.deepEqual(found.sort((a,b)=>a.id.localeCompare(b.id)),normalize(documents));
  seed = { created: 0, unchanged: 60 };
} else {
  await request(parent + ':commit', { writes: documents.map(x=>({
    update: { name: name(x.id), fields: fields(x.data) }, currentDocument: { exists: false }
  })) });
  seed = { created: 60, unchanged: 0 };
}
// CRUD uses only its own document and never deletes a pre-existing record.
const demoId = 'tre-phase2-crud-example';
const demoName = name(demoId);
const initial = structuredClone(documents[0].data);
let owned = false;
const crud = [];
try {
  await request(parent + ':commit', { writes: [{update:{name:demoName,fields:fields(initial)},currentDocument:{exists:false}}] });
  owned = true; crud.push({operation:'CREATE',document_id:demoId,success:true});
  const before = await request(demoName);
  assert.deepEqual(decodeDoc(before).data,normalize(initial));
  crud.push({operation:'READ',document:decodeDoc(before)});
  const changed = structuredClone(initial);
  changed.feedback.score=4;changed.follow_up.status='DONE';
  changed.updated_at=new Date(new Date(changed.updated_at).getTime()+60000).toISOString();
  await request(parent + ':commit', {writes:[{update:{name:demoName,fields:fields(changed)},currentDocument:{updateTime:before.updateTime}}]});
  const after=await request(demoName);
  assert.deepEqual(decodeDoc(after).data,normalize(changed));
  crud.push({operation:'UPDATE',document:decodeDoc(after)});
  await request(parent + ':commit',{writes:[{delete:demoName,currentDocument:{updateTime:after.updateTime}}]});
  owned=false;crud.push({operation:'DELETE',document_id:demoId,success:true});
} finally {
  if(owned) await request(parent+':commit',{writes:[{delete:demoName}]});
}
async function query(field,value,direction) {
  const result=await request(parent+':runQuery',{structuredQuery:{
    from:[{collectionId:collectionName}],
    where:{fieldFilter:{field:{fieldPath:field},op:'EQUAL',value:encode(value)}},
    orderBy:[{field:{fieldPath:'created_at'},direction}]
  }});
  return result.filter(x=>x.document).map(x=>({id:x.document.name.split('/').at(-1),...decodeDoc(x.document).data}));
}
const f01=await query('showing_id',1,'DESCENDING');
const f02=await query('follow_up.required',true,'ASCENDING');
const aggregate=await request(parent+':runAggregationQuery',{structuredAggregationQuery:{
  structuredQuery:{from:[{collectionId:collectionName}]},aggregations:[{alias:'total',count:{}}]
}});
const total=Number(aggregate.find(x=>x.result)?.result.aggregateFields.total.integerValue);
assert.equal(f01.length,3);assert.equal(f02.length,20);assert.equal(total,60);
const all=await request(`${parent}/${collectionName}?pageSize=100`);
assert(!all.nextPageToken);
const exported=all.documents.map(decodeDoc).sort((a,b)=>a.id.localeCompare(b.id));
assert.deepEqual(exported,normalize(documents));
const anonymous=await fetch(prefix+name(documents[0].id));
assert.equal(anonymous.status,403,'Anonymous cloud read must be denied');
const actualIndexes=indexes.indexes || [];
for(const expected of expectedIndexes) {
  assert(actualIndexes.some(index=>index.state==='READY' && index.queryScope===expected.queryScope &&
    expected.fields.every(field=>index.fields.some(x=>x.fieldPath===field.fieldPath && x.order===field.order))),
    'Expected composite index is not READY');
}
await saveJson('results/cloud/crud_operations.json',crud);
await saveJson('results/cloud/query_results.json',{F01_notes_for_showing:f01,F02_follow_up_required:f02,F03_total_count:total});
await saveJson('results/cloud/exported_documents.json',exported);
await saveJson('results/cloud/database.json',dbInfo);
await saveJson('results/cloud/indexes.json',indexes);
const summary={result:'PASS',mode:'CLOUD_FIRESTORE',project_id:project,database_id:'(default)',
  location:dbInfo.locationId,database_type:dbInfo.type,recorded_at_utc:new Date().toISOString(),
  documents:60,seed,crud_operations:['CREATE','READ','UPDATE','DELETE'],query_row_counts:{F01:3,F02:20,F03:60},
  seed_documents_unchanged_after_crud:true,anonymous_cloud_read_denied:true,
  cloud_composite_indexes_ready:2,authentication:'Existing official Firebase CLI OAuth login; no service-account key exported',
  transport:'Official Firestore REST API with in-memory OAuth access token',node_version:process.version};
await saveJson('results/cloud/summary.json',summary);
console.log(JSON.stringify(summary,null,2));

}

// START AND STOP THE OFFICIAL EMULATOR
function runEmulator() {
// Always launch the installed CLI with the same Node runtime as this script.
const env = { ...process.env, GCLOUD_PROJECT: projectId, GOOGLE_CLOUD_PROJECT: projectId };
const pathKey = Object.keys(env).find(key => key.toUpperCase() === 'PATH') || 'PATH';
env[pathKey] = path.dirname(process.execPath) + path.delimiter + (env[pathKey] || '');
// Windows packaged apps can redirect TEMP in a way Java Unix-domain pipes cannot
// use. A short, explicit JVM socket directory fixed that failure on the test host.
if (process.platform === 'win32' && !(env.JAVA_TOOL_OPTIONS || '').includes('jdk.net.unixdomain.tmpdir')) {
  const socketDir = path.join(os.homedir(), '.tre_phase2_java_tmp');
  mkdirSync(socketDir, { recursive: true });
  env.JAVA_TOOL_OPTIONS = ((env.JAVA_TOOL_OPTIONS || '') + ` -Djdk.net.unixdomain.tmpdir="${socketDir}"`).trim();
}
const result = spawnSync(process.execPath, [
  path.join(root, 'node_modules/firebase-tools/lib/bin/firebase.js'),
  'emulators:exec', '--only', 'firestore', '--project', projectId,
  'node firestore_demo.mjs --validate-local'
], { cwd: root, env, encoding: 'utf8', maxBuffer: 10 * 1024 * 1024 });
const log = (result.stdout || '') + (result.stderr || '') + (result.error ? '\n' + result.error : '');
process.stdout.write(log);
process.exit(result.status ?? 1);

}

// COMMAND LINE ENTRY POINT
const mode = process.argv[2] || '--help';
if (mode === '--emulator') runEmulator();
else if (mode === '--validate-local') await validateLocal();
else if (mode === '--cloud') await validateCloud();
else if (mode === '--check-data') {
  sampleData.documents.forEach(x => validateNote(x.data));
  assert.deepEqual(normalize(buildDocuments()), normalize(sampleData.documents));
  console.log(JSON.stringify({ result: 'PASS', documents: sampleData.documents.length, postgres_showings: references.showings.length }));
} else if (mode === '--export-data') {
  await writeFile(path.join(root, 'sample_data.json'), JSON.stringify({ postgres_references: references, documents: buildDocuments() }, null, 2) + '\n');
  console.log('Regenerated 60 notes from the captured PostgreSQL references.');
} else {
  assert(mode === '--help', 'Unknown option. Use --help.');
  console.log(`TotallyRealEstate Firestore demonstration
  node firestore_demo.mjs --check-data
  node firestore_demo.mjs --emulator
  node firestore_demo.mjs --export-data
  node firestore_demo.mjs --cloud --project totallyrealestate-phase-2 --write
The emulator is local. Cloud mode requires an existing official Firebase CLI login.`);
}
