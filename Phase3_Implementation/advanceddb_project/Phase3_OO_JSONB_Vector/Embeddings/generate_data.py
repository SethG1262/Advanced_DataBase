"""Create a deterministic fictional corpus linked to Phase 2 keys, before embedding.

One row is one listing/topic document, not one extra property. All descriptions
use the same property feature record. No web listings or personal data are used.
AI assistance: Codex authored the generator and sentence banks; no API is called.
"""
import hashlib
import json
import random
from collections import Counter
from common import connect, DATA, SQL, RESULTS, dump, csv_out, insert

QUERIES = [
 {'id':'S1','text':'A home with a quiet separate office and a door for private video meetings.','topic':'work','flag':'office'},
 {'id':'S2','text':'A private fenced backyard with outdoor space for a dog to play.','topic':'outdoor','flag':'fenced'},
 {'id':'S3','text':'Step free access from the entrance into the home without climbing stairs.','topic':'access','flag':'step_free'},
 {'id':'S4','text':'A parking space with a charger for an electric car at home.','topic':'parking','flag':'ev'},
 {'id':'S5','text':'A kitchen with an induction cooktop and an island for preparing meals.','topic':'kitchen','flag':'induction_island'}
]
TOPICS = ['overview','work','outdoor','access','parking','kitchen','transit','services','energy','layout']
AMENITIES = [(1,'Juniper Station','TRANSIT'),(2,'Cedar Station','TRANSIT'),(3,'Willow Station','TRANSIT'),
             (4,'Maple Green','PARK'),(5,'Oak Market','GROCERY'),(6,'Birch Library','LIBRARY')]

def property_details(p):
    rng = random.Random(20261117 + p['property_id']*7919)
    typ=p['property_type']
    office=rng.random()<.52
    fenced=typ in ('DETACHED','TOWNHOUSE') and rng.random()<.7
    step=rng.random()<.35
    ev=rng.random()<.3
    induction=rng.random()<.5
    island=rng.random()<.65
    station=rng.randint(1,3)
    distance=rng.choice([180,300,450,650,900,1400])
    flags=dict(office=office,fenced=fenced,step_free=step,ev=ev,induction_island=induction and island)
    f={'schema_version':1,'accessibility':{'step_free':step},'outdoor':{'fenced_yard':fenced},
       'workspace':{'separate_office':office},'parking':{'ev_charger':ev},
       'kitchen':{'induction':induction,'island':island},
       'nearby_amenities':[{'amenity_id':station,'distance_m':distance},{'amenity_id':4,'distance_m':rng.randint(2,14)*100}]}
    if rng.random()<.45: f['energy']={'heat_pump':True,'window_glazing':'triple'}
    return f, flags

def topic_body(topic,p,f,l):
    flag=lambda a,b: f[a][b]
    office=flag('workspace','separate_office'); fenced=flag('outdoor','fenced_yard')
    step=flag('accessibility','step_free'); ev=flag('parking','ev_charger')
    induction=flag('kitchen','induction'); island=flag('kitchen','island')
    station=AMENITIES[f['nearby_amenities'][0]['amenity_id']-1][1]
    dist=f['nearby_amenities'][0]['distance_m']
    descriptions={
     'overview':f"This {p['property_type'].lower()} property offers {p['bedrooms']} bedrooms and {p['bathrooms']} bathrooms across {p['floor_area_sqm']} square metres. The asking price for this listing is CAD {l['asking_price']}. The recorded listing status is {l['status'].lower().replace('_',' ')}. Buyers should use the structured fields to check price and availability before arranging a visit.",
     'work':('A separate home office has a full door that can be closed during private video meetings. There is room for a desk, chair and storage. This workspace supports focused remote work away from the main living room.' if office else 'The available desk area is an alcove in the main living room. It shares the social space and has no door or enclosed study. A person who needs a private room for video meetings would need to change the layout.'),
     'outdoor':('A private backyard is enclosed by a fence and has a level lawn where a dog can play. The rear door opens towards this outdoor area. There is space for a small table and gardening containers within the boundary.' if fenced else 'Outdoor space is shared or open at the boundary, without a private fenced yard. Residents can use the nearby park for outdoor activities. A buyer needing an enclosed area for a dog should review another property or plan an approved improvement.'),
     'access':('The route from the entrance to the main interior is step free, with no stairs along that path. The entry layout allows easier movement when carrying bags or using a mobility aid. This description does not certify accessibility standards or doorway clearances.' if step else 'A short flight of stairs connects the entrance to the main interior. The current entry route requires climbing steps and has no ramp. Buyers who require a step free entrance should check a different listing or assess whether an alteration is possible.'),
     'parking':('An assigned parking space includes an installed electric vehicle charger for charging a car at home. The space is close to the entrance, and the charger serves this property. Charging cost and electrical capacity would need to be confirmed before purchase.' if ev else 'The property has a designated parking space with ordinary vehicle access. No electric vehicle charger is installed in the space. A buyer considering an electric car would need an approved installation or a suitable public charging location.'),
     'kitchen':f"The kitchen uses {'an induction cooktop' if induction else 'a conventional electric coil cooktop'} and {'has a central island for preparing meals' if island else 'has counters along the wall without a central island'}. Cupboards provide everyday storage beside the cooking area. The layout connects to the dining space and gives access to the main living room.",
     'transit':f"{station} is the named transit stop for this listing, approximately {dist} metres from the entrance in this fictional dataset. The route links the property with local public transport. Buyers can compare the distance with their walking preferences, while service frequency and travel times require a separate timetable check.",
     'services':'The local area includes Oak Market for groceries and Birch Library for borrowing books and quiet study. Maple Green provides a public outdoor gathering space. These fictional amenities support a discussion of everyday convenience; opening hours and actual services are outside this training dataset.',
     'energy':('A heat pump and triple glazed windows are recorded as optional energy features. These systems can support indoor temperature control. No energy rating or utility savings are claimed, and operating cost depends on use, weather and the equipment condition.' if 'energy' in f else 'Heating and window specifications have not been supplied for this property. There is no verified heat pump or glazing upgrade in the feature record. Buyers would need an inspection and utility information before comparing energy performance or predicting operating costs.'),
     'layout':f"The floor plan contains {p['bedrooms']} bedrooms and {p['bathrooms']} bathrooms, with a recorded area of {p['floor_area_sqm']} square metres. Living and dining spaces form the everyday circulation route. The room count is a fixed property attribute shared across listing history, while the sale price and listing status belong to each separate listing."
    }
    intros=['This topic note covers','The following listing note describes','This property record outlines','The marketing note focuses on','This listing document explains']
    # Listing context creates genuine historical provenance; topic content is a separate document.
    return f"{intros[(l['listing_id']+TOPICS.index(topic))%5]} {topic} for {p['property_ref']} in {p['municipality']}, listed on {l['listed_on']}. {descriptions[topic]}"

def main():
    with connect() as c:
        properties=c.execute('SELECT * FROM tre.property ORDER BY property_id').fetchall()
        listings=c.execute('SELECT * FROM tre.listing ORDER BY listing_id').fetchall()
    pd={p['property_id']:p for p in properties}
    features={}; labels={}; statements=['BEGIN;\n']
    for values in AMENITIES:
        statements.append(insert('tre_p3.amenity',['amenity_id','name','kind'],values))
    for p in properties:
        k=p['property_id']; typ=p['property_type']; f,flags=property_details(p)
        features[k]=f; labels[k]=flags
        if typ=='DETACHED': table='detached_property'; cols=['property_id','lot_area_sqm']; vals=[k,350+k*2]
        elif typ=='CONDO': table='condo_property'; cols=['property_id','floor_number','monthly_condo_fee']; vals=[k,1+k%16,250+k%17*15]
        elif typ=='TOWNHOUSE': table='townhouse_property'; cols=['property_id','shared_walls']; vals=[k,1+k%2]
        else: table='other_property'; cols=['property_id','category_note']; vals=[k,'Unclassified residential form']
        statements.append(insert('tre_p3.'+table,cols,vals))
        statements.append(insert('tre_p3.property_features',['property_id','features'],[k,json.dumps(f)]))
    statements.append('COMMIT;\n')
    (SQL/'02_subtypes_and_features.sql').write_text(''.join(statements),encoding='utf-8')
    docs=[]
    for l in listings:
        p=pd[l['property_id']]; f=features[p['property_id']]
        for i,topic in enumerate(TOPICS):
            title=f"{topic.title()} note for listing {l['listing_id']}"
            body=topic_body(topic,p,f,l)
            docs.append({'document_id':(l['listing_id']-1)*10+i+1,'listing_id':l['listing_id'],
                         'property_id':p['property_id'],'topic':topic,'title':title,'body':body,
                         'source_text_sha256':hashlib.sha256((title+'\n'+body).encode()).hexdigest(),
                         'relevance_facts':labels[p['property_id']]})
    (DATA/'raw_documents.jsonl').write_text(''.join(json.dumps(d,default=str)+'\n' for d in docs),encoding='utf-8')
    statements=['BEGIN;\n']
    cols=['document_id','listing_id','topic','title','body','source_text_sha256']
    for d in docs: statements.append(insert('tre_p3.listing_document',cols,[d[k] for k in cols]))
    statements.append('COMMIT;\n')
    (SQL/'03_load_documents.sql').write_text(''.join(statements),encoding='utf-8')
    dump(DATA/'search_queries.json',QUERIES)
    qrels=[{'query_id':q['id'],'document_id':d['document_id'],'relevant':int(d['topic']==q['topic'] and d['relevance_facts'][q['flag']])}
           for q in QUERIES for d in docs]
    csv_out(DATA/'qrels.csv',qrels)
    lengths=[len(d['body']) for d in docs]
    audit={'source':'Deterministic fictional TRE topic documents generated by generate_data.py',
           'source_rows':len(docs),'clean_rows':len(docs),'properties':len(properties),'listings':len(listings),
           'grain':'One listing and one topic; 10 topics per listing',
           'empty_body':sum(not d['body'].strip() for d in docs),
           'short_under_40_characters':sum(n<40 for n in lengths),
           'duplicate_document_ids':len(docs)-len({d['document_id'] for d in docs}),
           'duplicate_bodies':len(docs)-len({d['body'] for d in docs}),
           'duplicate_full_embedded_text':len(docs)-len({d['source_text_sha256'] for d in docs}),
           'orphan_listing_keys':sum(d['listing_id'] not in {l['listing_id'] for l in listings} for d in docs),
           'characters_min':min(lengths),'characters_max':max(lengths),
           'characters_mean':round(sum(lengths)/len(lengths),2),
           'topics':dict(Counter(d['topic'] for d in docs)),
           'cleaning':'Trim generated text; retain all rows. Exact duplicates audited. Semantic repetition from templates and relistings is documented.',
           'token_audit':'Added after the pinned model tokenizer runs in embed.py.'}
    dump(RESULTS/'data_audit.json',audit)
    print(f'Generated {len(docs)} documents and saved pre-embedding qrels; {audit["duplicate_bodies"]} exact body duplicates.')

if __name__=='__main__': main()
