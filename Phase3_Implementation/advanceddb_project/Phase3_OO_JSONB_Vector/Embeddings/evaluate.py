"""Run real searches, export complete results/plans, evaluate predeclared qrels.

Relevance is an explicit synthetic benchmark rule, written before retrieval.
It is assistant-authored and reproducible, not claimed to be a human user study.
"""
import csv
import json
import statistics
import time
from datetime import datetime,timezone
from common import connect, DATA, SQL, RESULTS, dump, csv_out, quote
from queries import JSON_QUERIES,VECTOR,FILTERED,COMBINED,HYBRID

def plan(c,name,sql):
    text=c.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) '+sql).fetchall()
    (RESULTS/(name+'.txt')).write_text('\n'.join(next(iter(row.values())) for row in text)+'\n',encoding='utf-8')
    value=c.execute('EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) '+sql).fetchone()['QUERY PLAN']
    dump(RESULTS/(name+'.json'),value)
    return value[0]

def timed(c,sql):
    c.execute(sql).fetchall() # warm-up outside measured repeats
    times=[]
    for _ in range(7):
        start=time.perf_counter(); c.execute(sql).fetchall(); times.append((time.perf_counter()-start)*1000)
    return {'repeats':7,'milliseconds':times,'median_ms':statistics.median(times),'cache':'warm','measurement':'client execute plus fetch'}

def main():
    qvs=json.loads((DATA/'query_vectors.json').read_text())
    vec=lambda q: quote('['+','.join(format(x,'.9g') for x in qvs[q]['vector'])+']')
    qs=json.loads((DATA/'search_queries.json').read_text())
    with (DATA/'qrels.csv').open(newline='',encoding='utf-8') as f:
        rel={(r['query_id'],int(r['document_id'])):int(r['relevant']) for r in csv.DictReader(f)}
    summary={'recorded_at_utc':datetime.now(timezone.utc).isoformat(),'queries':[],
             'relevance_method':'Predeclared topic plus positive feature rubric; assistant-authored synthetic qrels, not independent human labels.',
             'result_grain':'Document for S1-S5 and hybrid; one listing for D1.'}
    search_settings="SET hnsw.ef_search=200;\nSET hnsw.iterative_scan='strict_order';\n"
    examples=["-- Executed query examples. Literal vectors use the pinned model and the named search text.\n"+search_settings]
    with connect() as c:
        c.autocommit=True
        c.execute('SET hnsw.ef_search=200')
        c.execute("SET hnsw.iterative_scan='strict_order'")
        summary['server']=c.execute('SELECT version() AS version').fetchone()['version']
        summary['pgvector_version']=c.execute("SELECT extversion FROM pg_extension WHERE extname='vector'").fetchone()['extversion']
        summary['hnsw']={'ef_search':200,'iterative_scan':'strict_order','m':16,'ef_construction':64}
        oo=c.execute('SELECT property_id,property_type,subclass_summary FROM tre_p3.property_catalog ORDER BY property_id LIMIT 8').fetchall()
        csv_out(RESULTS/'A1_polymorphism.csv',oo)
        for name,sql in JSON_QUERIES.items():
            rows=c.execute(sql).fetchall(); csv_out(RESULTS/(name+'.csv'),rows)
        with c.transaction(force_rollback=True):
            before=c.execute('SELECT features FROM tre_p3.property_features WHERE property_id=1').fetchone()
            desired=not before['features']['outdoor']['fenced_yard']
            after=c.execute('SELECT tre_p3.set_fenced_yard(1,%s) AS features',(desired,)).fetchone()
            dump(RESULTS/'J4_nested_update.json',{'before':before,'after':after,'transaction':'Rolled back after demonstration'})
        jsql=JSON_QUERIES['J1_containment']
        plan(c,'J1_default_plan',jsql)
        with c.transaction(force_rollback=True):
            c.execute('SET LOCAL enable_seqscan=off')
            c.execute('SET LOCAL enable_indexscan=off')
            plan(c,'J1_gin_diagnostic_plan',jsql)
        for q in qs:
            sql=VECTOR.format(vec=vec(q['id']),limit=5)
            rows=c.execute(sql).fetchall()
            plan(c,q['id']+'_plan',sql)
            for rank,row in enumerate(rows,1):
                row['rank']=rank; row['relevant']=rel[q['id'],row['document_id']]
                row['relevance_reason']=f"Requires topic={q['topic']} and {q['flag']}=true; evaluated against predeclared corpus facts."
            csv_out(RESULTS/(q['id']+'_top5.csv'),rows)
            n=sum(r['relevant'] for r in rows)
            summary['queries'].append({'query_id':q['id'],'query':q['text'],'returned':len(rows),'relevant':n,'precision_at_5':n/5})
            examples.append('-- '+q['id']+': '+q['text']+'\n'+sql+';\n')
        summary['mean_precision_at_5']=statistics.mean(r['precision_at_5'] for r in summary['queries'])
        for name,template,q in [('C1_filtered',FILTERED,'FILTER'),('D1_combined',COMBINED,'FILTER')]:
            sql=template.format(vec=vec(q)); rows=c.execute(sql).fetchall()
            csv_out(RESULTS/(name+'.csv'),rows)
            plan(c,name+'_plan',sql)
            summary[name]={'rows_returned':len(rows),'unique_listings':len({r['listing_id'] for r in rows})}
            (SQL/(name+'.sql')).write_text(search_settings+sql+';\n',encoding='utf-8')
            examples.append(sql+';\n')
        for name,sql in [('C2_vector_only',VECTOR.format(vec=vec('HYBRID'),limit=5)),('C2_hybrid',HYBRID.format(vec=vec('HYBRID')))]:
            rows=c.execute(sql).fetchall()
            for r in rows: r['exact_station_relevant']=int(r['topic']=='transit' and 'Juniper Station' in r['body'])
            csv_out(RESULTS/(name+'.csv'),rows)
            summary[name]={'exact_station_relevant':sum(r['exact_station_relevant'] for r in rows),'precision_at_5':sum(r['exact_station_relevant'] for r in rows)/5}
            examples.append('-- '+qvs['HYBRID']['text']+'\n'+sql+';\n')
        sql=VECTOR.format(vec=vec('S1'),limit=10)
        comparison={}
        for mode in ['exact','hnsw']:
            with c.transaction(force_rollback=True):
                if mode=='exact':
                    c.execute('SET LOCAL enable_indexscan=off'); c.execute('SET LOCAL enable_bitmapscan=off')
                else: c.execute('SET LOCAL enable_seqscan=off')
                rows=c.execute(sql).fetchall(); csv_out(RESULTS/('C3_'+mode+'_top10.csv'),rows)
                pl=plan(c,'C3_'+mode+'_plan',sql)
                comparison[mode]={'document_ids':[r['document_id'] for r in rows],**timed(c,sql),
                                  'explain_execution_ms':pl['Execution Time']}
        intersection=set(comparison['exact']['document_ids'])&set(comparison['hnsw']['document_ids'])
        comparison.update(top10_matches=len(intersection),recall_at_10=len(intersection)/10,
                          settings_note='Exact disables index and bitmap scans. HNSW disables sequential scans. Plans saved to verify paths; other settings identical.')
        summary['index_comparison']=comparison
        summary['baseline_counts']=c.execute("SELECT (SELECT count(*) FROM tre.property) AS properties,(SELECT count(*) FROM tre.listing) AS listings,(SELECT count(*) FROM tre_p3.listing_document) AS documents,(SELECT count(*) FROM tre_p3.listing_document WHERE embedding IS NOT NULL) AS embeddings").fetchone()
    dump(RESULTS/'evaluation_summary.json',summary)
    csv_out(RESULTS/'precision_at_5.csv',summary['queries'])
    (SQL/'07_vector_search_examples.sql').write_text('\n'.join(examples),encoding='utf-8')
    (SQL/'06_oo_jsonb_examples.sql').write_text("SELECT property_id,property_type,subclass_summary FROM tre_p3.property_catalog ORDER BY property_id LIMIT 8;\n\n"+';\n\n'.join(JSON_QUERIES.values())+";\n\nEXPLAIN (ANALYZE,BUFFERS) "+JSON_QUERIES['J1_containment']+";\n\nBEGIN;\nSELECT tre_p3.set_fenced_yard(1,true);\n-- Encapsulated implementation uses jsonb_set; rollback preserves the captured corpus.\nROLLBACK;\n",encoding='utf-8')
    print(json.dumps({'mean_precision_at_5':summary['mean_precision_at_5'],'top10_matches':len(intersection),'combined_rows':summary['D1_combined']['rows_returned']}))

if __name__=='__main__': main()
