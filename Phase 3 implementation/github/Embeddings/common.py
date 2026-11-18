"""Shared paths and credential-free PostgreSQL helpers. Uses standard PG* variables."""
from pathlib import Path
import csv
import json
import os
import psycopg
from psycopg.rows import dict_row

ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / 'Query_Results'
DATA = ROOT / 'Embeddings'
SQL = ROOT / 'SQL_Scripts'
MODEL = 'sentence-transformers/all-MiniLM-L6-v2'

def connect():
    if not os.environ.get('PGDATABASE'):
        raise RuntimeError('Set PGDATABASE and your other PG* connection variables first.')
    return psycopg.connect('', row_factory=dict_row)

def dump(path, value):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False, default=str)+'\n', encoding='utf-8')

def csv_out(path, rows):
    rows = list(rows)
    if not rows:
        Path(path).write_text('', encoding='utf-8'); return
    with Path(path).open('w', newline='', encoding='utf-8') as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader(); w.writerows(rows)

def quote(value):
    if value is None: return 'NULL'
    if isinstance(value, bool): return 'true' if value else 'false'
    if isinstance(value, (int,float)): return str(value)
    return "'"+str(value).replace("'", "''")+"'"

def insert(table, columns, values):
    return f'INSERT INTO {table} ({",".join(columns)}) VALUES ({",".join(quote(v) for v in values)});\n'
