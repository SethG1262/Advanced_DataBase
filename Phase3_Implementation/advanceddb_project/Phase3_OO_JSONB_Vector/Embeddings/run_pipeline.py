"""Rebuild on a NEW empty database; optionally regenerate corpus/vectors for bonus.

Example: python Embeddings/run_pipeline.py --regenerate
Uses PGHOST, PGPORT, PGUSER, PGDATABASE, PGPASSFILE or a normal libpq prompt setup.
Never drops a database. The server must have pgvector installed.
"""
import argparse
import subprocess
import sys
from common import connect,SQL

def run_script(name):
    subprocess.run([sys.executable,str(SQL.parent/'Embeddings'/name)],check=True)

def sql_file(path):
    # One connection per file; the files own their BEGIN/COMMIT boundaries.
    with connect() as c:
        c.autocommit=True
        c.execute(path.read_text(encoding='utf-8'),prepare=False)

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--regenerate',action='store_true',help='Regenerate documents, qrels and embeddings from the pinned model before loading.')
    args=ap.parse_args()
    with connect() as c:
        if c.execute("SELECT 1 FROM pg_namespace WHERE nspname IN ('tre','tre_p3')").fetchone():
            raise RuntimeError('Use a new empty database. Existing tre or tre_p3 schema found; nothing has been dropped.')
    for path in sorted((SQL/'phase2_baseline').glob('*.sql')): sql_file(path)
    if args.regenerate: run_script('generate_data.py')
    for name in ['01_phase3_schema.sql','02_subtypes_and_features.sql','03_load_documents.sql']: sql_file(SQL/name)
    if args.regenerate: run_script('embed.py')
    sql_file(SQL/'04_load_vectors.sql')
    run_script('build_indexes.py')
    run_script('evaluate.py')
    run_script('validate.py')
    print('Rebuild, search evaluation and integration tests completed.')

if __name__=='__main__': main()
