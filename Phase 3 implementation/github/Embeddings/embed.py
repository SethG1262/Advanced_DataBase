"""Generate real CPU embeddings and a portable SQL loader using a pinned free model."""
import hashlib
import importlib.metadata
import json
import platform
import time
import numpy as np
import torch
from huggingface_hub import HfApi
from sentence_transformers import SentenceTransformer
from common import DATA, SQL, RESULTS, MODEL, dump, quote

def main():
    torch.set_num_threads(4)
    torch.manual_seed(20261117)
    manifest_path=DATA/'model_manifest.json'
    previous=json.loads(manifest_path.read_text()) if manifest_path.exists() else {}
    revision=previous.get('revision') or HfApi().model_info(MODEL).sha
    print('Loading model',MODEL,'revision',revision,flush=True)
    start=time.perf_counter()
    model=SentenceTransformer(MODEL,revision=revision,device='cpu')
    docs=[json.loads(s) for s in (DATA/'raw_documents.jsonl').read_text(encoding='utf-8').splitlines()]
    texts=[d['title']+'\n'+d['body'] for d in docs]
    token_lengths=[len(ids) for ids in model.tokenizer(texts,truncation=False,add_special_tokens=True)['input_ids']]
    cutoff=model.max_seq_length
    vectors=model.encode(texts,batch_size=64,normalize_embeddings=True,show_progress_bar=True,convert_to_numpy=True)
    np.save(DATA/'document_vectors.npy',vectors)
    queries=json.loads((DATA/'search_queries.json').read_text())
    queries += [{'id':'FILTER','text':'A quiet separate office for working from home with privacy.'},
                {'id':'HYBRID','text':'A home close to Juniper Station for commuting by public transport.'}]
    qvectors=model.encode([q['text'] for q in queries],normalize_embeddings=True,convert_to_numpy=True)
    dump(DATA/'query_vectors.json',{q['id']:{'text':q['text'],'vector':v.tolist()} for q,v in zip(queries,qvectors)})
    with (SQL/'04_load_vectors.sql').open('w',encoding='utf-8') as f:
        f.write('-- Real normalized all-MiniLM-L6-v2 embeddings; regenerate with Embeddings/embed.py.\nBEGIN;\n')
        for d,v in zip(docs,vectors):
            value='['+','.join(format(float(x),'.9g') for x in v)+']'
            f.write(f"UPDATE tre_p3.listing_document SET embedding={quote(value)}::public.vector, embedding_model={quote(MODEL)}, embedding_revision={quote(revision)}, embedded_text_sha256={quote(d['source_text_sha256'])} WHERE document_id={d['document_id']} AND source_text_sha256={quote(d['source_text_sha256'])};\n")
        f.write('DO $$ BEGIN IF EXISTS(SELECT 1 FROM tre_p3.listing_document WHERE embedding IS NULL) THEN RAISE EXCEPTION \'Missing vectors or source hash mismatch\'; END IF; END $$;\nCOMMIT;\n')
    elapsed=time.perf_counter()-start
    manifest={'model':MODEL,'revision':revision,'dimensions':int(vectors.shape[1]),'licence':'Apache-2.0',
              'model_url':'https://huggingface.co/'+MODEL,'device':'CPU','threads':4,
              'max_sequence_length':cutoff,'pooling':'SentenceTransformer model configured mean pooling',
              'normalized':True,'distance':'cosine','index':'HNSW vector_cosine_ops','document_count':len(docs),
              'input':'title + newline + body','dtype':str(vectors.dtype),'python':platform.python_version(),
              'packages':{p:importlib.metadata.version(p) for p in ['sentence-transformers','transformers','torch','numpy','psycopg','pgvector','huggingface-hub']},
              'model_load_and_generation_seconds':round(elapsed,3),
              'vector_file_sha256':hashlib.sha256((DATA/'document_vectors.npy').read_bytes()).hexdigest()}
    dump(manifest_path,manifest)
    audit=json.loads((RESULTS/'data_audit.json').read_text())
    audit.update(token_count_min=min(token_lengths),token_count_max=max(token_lengths),
                 token_count_mean=round(float(np.mean(token_lengths)),2),model_token_limit=cutoff,
                 rows_exceeding_model_limit=sum(n>cutoff for n in token_lengths),
                 truncation_handling='No source truncation required.' if max(token_lengths)<=cutoff else 'Model truncates at its configured token limit; raw text retained.',
                 empty_vectors=int(np.isnan(vectors).any(axis=1).sum()),token_audit='Includes title, newline and tokenizer special tokens.')
    dump(RESULTS/'data_audit.json',audit)
    print('Generated',vectors.shape,'in',round(elapsed,1),'seconds; over-limit texts:',audit['rows_exceeding_model_limit'],flush=True)

if __name__=='__main__': main()
