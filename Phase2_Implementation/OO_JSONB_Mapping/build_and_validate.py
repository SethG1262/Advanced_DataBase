"""Export actual PostgreSQL rows -> dataclasses -> JSON -> PostgreSQL JSONB.

No third-party Python package is needed. Install 00_schema.sql before running.
The generated 01_load_snapshots.sql performs an explicit snapshot refresh/upsert.
"""
import argparse
from collections import defaultdict
import csv
from datetime import datetime, timezone
from decimal import Decimal
import io
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
from models import AgentSummary,ClientSummary,Listing,Money,OfferSummary,PropertySummary

ROOT=Path(__file__).resolve().parent


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--host',default='127.0.0.1')
    p.add_argument('--port',type=int,default=5432)
    p.add_argument('--user',required=True)
    p.add_argument('--database',required=True)
    p.add_argument('--psql',default=shutil.which('psql') or r'C:\Program Files\PostgreSQL\18\bin\psql.exe')
    args=p.parse_args()
    env=dict(os.environ,PGCLIENTENCODING='UTF8')
    base=[args.psql,'-X','-q','-v','ON_ERROR_STOP=1','-h',args.host,'-p',str(args.port),'-U',args.user,'-d',args.database]
    def run(statement,extra=()):
        r=subprocess.run([*base,*extra],input=statement,text=True,encoding='utf-8',capture_output=True,env=env,timeout=40)
        if r.returncode:raise RuntimeError(r.stderr)
        return r.stdout
    tables=['client','agent','staff','property','listing','listing_seller','showing','showing_booking','offer','offer_buyer','sale_transaction']
    parts=[]
    for t in tables:
        parts.append(f"'{t}',(SELECT coalesce(json_agg(row_to_json(x)),'[]'::json) FROM tre.{t} x)")
    raw=json.loads(run('SELECT json_build_object('+','.join(parts)+');',('-At',)),parse_float=Decimal)
    clients={x['client_id']:x for x in raw['client']}
    agents={x['agent_id']:x for x in raw['agent']}
    properties={x['property_id']:x for x in raw['property']}
    sellers=defaultdict(list);buyers=defaultdict(list);offers=defaultdict(list)
    def person(cid):
        c=clients[cid]
        return ClientSummary(cid,c['first_name']+' '+c['last_name'])
    for x in sorted(raw['listing_seller'],key=lambda x:(x['listing_id'],x['client_id'])):
        sellers[x['listing_id']].append(person(x['client_id']))
    for x in sorted(raw['offer_buyer'],key=lambda x:(x['offer_id'],x['client_id'])):
        buyers[x['offer_id']].append(person(x['client_id']))
    for x in sorted(raw['offer'],key=lambda x:x['offer_id']):
        offers[x['listing_id']].append(OfferSummary(x['offer_id'],x['status'],Money(Decimal(x['offer_amount'])),x['submitted_at'],tuple(buyers[x['offer_id']])))
    objects=[]
    for x in sorted(raw['listing'],key=lambda x:x['listing_id']):
        prop=properties[x['property_id']];agent=agents[x['agent_id']]
        objects.append(Listing(x['listing_id'],x['status'],Money(Decimal(x['asking_price'])),x['listed_on'],x['closed_on'],
            PropertySummary(**{k:prop[k] for k in ('property_id','property_ref','address_text','municipality','property_type')}),
            AgentSummary(agent['agent_id'],agent['first_name']+' '+agent['last_name'],agent['license_number']),
            tuple(sellers[x['listing_id']]),tuple(offers[x['listing_id']])))
    payloads=[x.to_dict() for x in objects]
    assert all(Listing.from_dict(d).to_dict()==d for d in payloads)
    captured=datetime.now(timezone.utc).isoformat()
    
    (ROOT/'listing_snapshots.json').write_text(json.dumps(payloads,indent=2),encoding='utf-8')
    encoded=json.dumps(payloads,separators=(',',':')).replace("'","''")
    load="-- Generated from actual tre rows through the typed Listing model.\nBEGIN;\n"
    load+="INSERT INTO tre_oo.listing_snapshot(listing_id,schema_version,captured_at,payload)\n"
    load+=f"SELECT (d->>'listing_id')::bigint,(d->>'schema_version')::integer,timestamptz '{captured}',d\n"
    load+=f"FROM jsonb_array_elements('{encoded}'::jsonb) d\n"
    load+="ON CONFLICT(listing_id) DO UPDATE SET schema_version=excluded.schema_version,captured_at=excluded.captured_at,payload=excluded.payload;\nCOMMIT;\nANALYZE tre_oo.listing_snapshot;\n"
    (ROOT/'01_load_snapshots.sql').write_text(load,encoding='utf-8')
    run(load)
    expected={'J01':1,'J02':13,'J03':65,'J04':125}
    query_rows={};query_results={}
    query_source=(ROOT/'JSONB_Queries.sql').read_text(encoding='utf-8')
    for key,statement in re.findall(r'-- =+ BEGIN (J\d\d) =+\n(.*?)-- =+ END \1 =+',query_source,re.S):
        out=run(statement,('--csv',))
        reader=csv.DictReader(io.StringIO(out));rows=list(reader)
        assert len(rows)==expected[key],(key,len(rows))
        query_rows[key]=len(rows)
        query_results[key]={'columns':reader.fieldnames,'row_count':len(rows),'rows':rows}
    assert set(query_results)==set(expected)
    # Check every captured amount/status against authoritative rows at capture time.
    checks=run("""SELECT count(*) FROM tre_oo.listing_snapshot s JOIN tre.listing l USING(listing_id)
        WHERE s.payload->>'status'<>l.status OR (s.payload#>>'{asking_price,amount}')::numeric<>l.asking_price
           OR (s.payload#>>'{property,property_id}')::bigint<>l.property_id
           OR (s.payload#>>'{agent,agent_id}')::bigint<>l.agent_id;""",('-At',)).strip()
    assert checks=='0'
    # Field-shape constraints must actually reject malformed or mismatched JSON.
    negative="""BEGIN;
    DO $$ DECLARE rejected boolean:=false; BEGIN
      BEGIN UPDATE tre_oo.listing_snapshot SET payload=payload||'{"listing_id":999999}'::jsonb WHERE listing_id=1;
      EXCEPTION WHEN check_violation THEN rejected:=true; END;
      IF NOT rejected THEN RAISE EXCEPTION 'Mismatched snapshot identity accepted'; END IF;
    END $$;
    DO $$ DECLARE rejected boolean:=false; BEGIN
      BEGIN UPDATE tre_oo.listing_snapshot SET payload=payload||'{"sellers":{}}'::jsonb WHERE listing_id=1;
      EXCEPTION WHEN check_violation THEN rejected:=true; END;
      IF NOT rejected THEN RAISE EXCEPTION 'Malformed seller collection accepted'; END IF;
    END $$;
    ROLLBACK;"""
    run(negative)
    # The Firestore prototype consumes a non-sensitive ID/time reference manifest.
    notes_path=ROOT.parent/'NoSQL_Prototype'/'sample_data.json'
    refs=sorted((x for x in raw['showing'] if x['status']=='COMPLETED'),key=lambda x:x['showing_id'])[:20]
    assert len(refs)==20
    notes_manifest={'captured_at_utc':captured,'source':'tre showing rows from the verified synthetic PostgreSQL seed',
        'showings':[{'showing_id':x['showing_id'],'listing_id':x['listing_id'],'agent_id':x['agent_id'],'ends_at':x['ends_at']} for x in refs]}
    note_data=json.loads(notes_path.read_text(encoding='utf-8'))
    note_data['postgres_references']=notes_manifest
    notes_path.write_text(json.dumps(note_data,indent=2)+'\n',encoding='utf-8')
    summary={'result':'PASS','listing_objects':len(objects),'json_round_trips':len(objects),'jsonb_rows':len(payloads),
        'query_rows':query_rows,'relational_mismatches_at_capture':0,'negative_shape_tests':2,
        'captured_at_utc':captured,'authority':'tre normalized tables; tre_oo is a replaceable read snapshot'}
    (ROOT/'Results.json').write_text(json.dumps({'queries':query_results,'summary':summary},indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary,indent=2))


if __name__=='__main__':main()
