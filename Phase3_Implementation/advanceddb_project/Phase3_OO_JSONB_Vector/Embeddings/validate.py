"""Integration tests for hierarchy integrity, JSONB, provenance and vector loading.

All mutation tests roll back. No existing database or table is dropped.
"""
import hashlib
import json
from datetime import datetime,timezone
import numpy as np
import psycopg
from pgvector.psycopg import register_vector
from common import connect, DATA, RESULTS, dump, csv_out
from queries import JSON_QUERIES

def main():
    checks=[]
    with connect() as c:
        register_vector(c)
        c.commit(); c.autocommit=True
        def check(name,condition,detail=''):
            checks.append({'test':name,'result':'PASS' if condition else 'FAIL','detail':detail})
            if not condition: raise AssertionError(name)
        def reject(name,sql,states):
            try:
                with c.transaction(force_rollback=True):
                    c.execute(sql); c.execute('SET CONSTRAINTS ALL IMMEDIATE')
            except psycopg.Error as e:
                check(name,e.sqlstate in states,'Rejected with SQLSTATE '+str(e.sqlstate))
            else: check(name,False,'Invalid mutation unexpectedly accepted')
        counts=c.execute("SELECT (SELECT count(*) FROM tre.property) AS properties,(SELECT count(*) FROM tre.listing) AS listings,(SELECT count(*) FROM tre_p3.listing_document) AS documents").fetchone()
        check('Baseline keys and 2500 text documents',counts=={'properties':200,'listings':250,'documents':2500})
        subs=c.execute("SELECT (SELECT count(*) FROM tre_p3.detached_property)+(SELECT count(*) FROM tre_p3.condo_property)+(SELECT count(*) FROM tre_p3.townhouse_property)+(SELECT count(*) FROM tre_p3.other_property) AS n").fetchone()['n']
        check('Complete subtype coverage',subs==200)
        k=c.execute('SELECT property_id FROM tre_p3.detached_property ORDER BY property_id LIMIT 1').fetchone()['property_id']
        reject('Wrong subclass membership',f'INSERT INTO tre_p3.condo_property VALUES({k},2,300)',{'23514'})
        reject('Missing subtype at transaction end',f'DELETE FROM tre_p3.detached_property WHERE property_id={k}',{'23514'})
        reject('Parent discriminator mismatch',f"UPDATE tre.property SET property_type='CONDO' WHERE property_id={k}",{'23514'})
        reject('Immutable subtype key',f'UPDATE tre_p3.detached_property SET property_id=999999 WHERE property_id={k}',{'23514'})
        reject('Negative lot size',f'UPDATE tre_p3.detached_property SET lot_area_sqm=-1 WHERE property_id={k}',{'23514'})
        reject('Negative condo fee','UPDATE tre_p3.condo_property SET monthly_condo_fee=-1',{'23514'})
        reject('JSON root must be an object',"UPDATE tre_p3.property_features SET features='[]' WHERE property_id=1",{'23514'})
        reject('Required JSON key',"UPDATE tre_p3.property_features SET features=features-'accessibility' WHERE property_id=1",{'23514'})
        reject('JSON null does not bypass CHECK',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{outdoor,fenced_yard}','null') WHERE property_id=1",{'23514'})
        reject('Boolean type is strict',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{outdoor,fenced_yard}','\"yes\"') WHERE property_id=1",{'23514'})
        reject('Nonnegative amenity distance',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,distance_m}','-10') WHERE property_id=1",{'23514'})
        reject('Amenity ID must be integral',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,amenity_id}','2.5') WHERE property_id=1",{'23514'})
        reject('Amenity ID fits bigint',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,amenity_id}','9223372036854775808') WHERE property_id=1",{'23514'})
        reject('Amenity key exists',"UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,amenity_id}','999') WHERE property_id=1",{'23503'})
        reject('Referenced catalogue protected','DELETE FROM tre_p3.amenity WHERE amenity_id=1',{'23514'})
        reject('Operation rejects null boolean','SELECT tre_p3.set_fenced_yard(1,NULL)',{'23514'})
        reject('Operation rejects unknown property','SELECT tre_p3.set_fenced_yard(999999,true)',{'P0002'})
        reject('Document listing FK','UPDATE tre_p3.listing_document SET listing_id=999999 WHERE document_id=1',{'23503'})
        reject('Short source text','UPDATE tre_p3.listing_document SET body=\'short\' WHERE document_id=1',{'23514'})
        reject('Vector dimension must match model',"UPDATE tre_p3.listing_document SET embedding='[1,2,3]' WHERE document_id=1",{'22000'})
        reject('Vector provenance hash must match',"UPDATE tre_p3.listing_document SET embedded_text_sha256=repeat('0',64) WHERE document_id=1",{'23514'})
        with c.transaction(force_rollback=True):
            c.execute("UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,amenity_id}','2.0') WHERE property_id=1")
            joined=c.execute(JSON_QUERIES['J3_array_join']).fetchall()
            name=c.execute('SELECT name FROM tre_p3.amenity WHERE amenity_id=2').fetchone()['name']
            check('Integral decimal JSON ID joins correctly',any(r['property_id']==1 and r['name']==name for r in joined))
        with c.transaction(force_rollback=True):
            c.execute("UPDATE tre_p3.property_features SET features=jsonb_set(features,'{nearby_amenities,0,distance_m}','400.5') WHERE property_id=1")
            joined=c.execute(JSON_QUERIES['J3_array_join']).fetchall()
            check('Array join preserves fractional distance',any(r['property_id']==1 and float(r['distance_m'])==400.5 for r in joined))
        with c.transaction(force_rollback=True):
            before=c.execute('SELECT features FROM tre_p3.property_features WHERE property_id=1').fetchone()['features']
            after=c.execute('SELECT tre_p3.set_fenced_yard(1,%s) AS f',(not before['outdoor']['fenced_yard'],)).fetchone()['f']
            expected=json.loads(json.dumps(before)); expected['outdoor']['fenced_yard']=not before['outdoor']['fenced_yard']
            check('Encapsulated nested update preserves other keys',after==expected)
        with c.transaction(force_rollback=True):
            c.execute("UPDATE tre_p3.listing_document SET body=body||' Text changed for a validation test.' WHERE document_id=1")
            row=c.execute('SELECT * FROM tre_p3.listing_document WHERE document_id=1').fetchone()
            check('Text edits invalidate derived embeddings',row['embedding'] is None and row['embedded_text_sha256'] is None)
            check('Text hash recomputed in database',row['source_text_sha256']==hashlib.sha256((row['title']+'\n'+row['body']).encode()).hexdigest())
        rows=c.execute('SELECT * FROM tre_p3.listing_document ORDER BY document_id').fetchall()
        expected=np.load(DATA/'document_vectors.npy')
        actual=np.asarray([r['embedding'].to_numpy() if hasattr(r['embedding'],'to_numpy') else r['embedding'] for r in rows])
        check('All vectors loaded at model dimensions',actual.shape==(2500,384))
        check('No invalid or zero vectors',bool(np.isfinite(actual).all() and (np.linalg.norm(actual,axis=1)>0).all()))
        check('Normalized vectors',bool(np.allclose(np.linalg.norm(actual,axis=1),1,atol=1e-6)))
        check('SQL vector load matches generated float32 values',bool(np.allclose(actual,expected,atol=1e-8,rtol=1e-7)))
        check('All text and embedding hashes match',all(r['source_text_sha256']==r['embedded_text_sha256']==hashlib.sha256((r['title']+'\n'+r['body']).encode()).hexdigest() for r in rows))
        check('All four polymorphic summaries present',len({r['property_type'] for r in c.execute('SELECT * FROM tre_p3.property_catalog').fetchall()})==4)
        check('Nested update rolled back',c.execute('SELECT features FROM tre_p3.property_features WHERE property_id=1').fetchone()['features']==before)
    summary={'result':'PASS','recorded_at_utc':datetime.now(timezone.utc).isoformat(),'passed':len(checks),'failed':0,'checks':checks}
    dump(RESULTS/'validation_summary.json',summary); csv_out(RESULTS/'validation_checks.csv',checks)
    print(f'{len(checks)} integration checks passed.')

if __name__=='__main__': main()
