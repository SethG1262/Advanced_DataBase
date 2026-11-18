import time
from common import connect, SQL, RESULTS, dump

def main():
    records=[]
    with connect() as c:
        c.autocommit=True
        for stmt in (SQL/'05_indexes.sql').read_text().split(';'):
            if not stmt.strip(): continue
            start=time.perf_counter(); c.execute(stmt)
            records.append({'statement':stmt.strip(),'elapsed_ms':round((time.perf_counter()-start)*1000,3)})
        sizes=c.execute("SELECT indexrelname,pg_relation_size(indexrelid) AS bytes FROM pg_stat_user_indexes WHERE schemaname='tre_p3' ORDER BY indexrelname").fetchall()
    dump(RESULTS/'index_build.json',{'statements':records,'index_sizes':sizes})
    print('Indexes created and timed.')
if __name__=='__main__': main()
