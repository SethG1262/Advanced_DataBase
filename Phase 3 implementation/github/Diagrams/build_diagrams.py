"""Generate editable SVG and draw.io sources. PNG rendering uses sharp or an SVG viewer."""
from pathlib import Path
import html
import xml.etree.ElementTree as ET

OUT=Path(__file__).resolve().parent

class Diagram:
    def __init__(self,w,h):
        self.w,self.h=w,h;self.parts=[f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}"><rect width="100%" height="100%" fill="white"/>']
        self.model=ET.Element('mxfile',host='app.diagrams.net');dia=ET.SubElement(self.model,'diagram',name='Diagram')
        graph=ET.SubElement(dia,'mxGraphModel',dx=str(w),dy=str(h),page='1',pageWidth=str(w),pageHeight=str(h))
        self.root=ET.SubElement(graph,'root');ET.SubElement(self.root,'mxCell',id='0');ET.SubElement(self.root,'mxCell',id='1',parent='0');self.i=1
    def text(self,x,y,t,size=20,anchor='start',bold=False):
        self.parts.append(f'<text x="{x}" y="{y}" font-family="Arial,sans-serif" font-size="{size}" font-weight="{"bold" if bold else "normal"}" text-anchor="{anchor}" fill="#172334">{html.escape(t)}</text>')
    def box(self,key,x,y,w,h,title,lines,methods=()):
        self.parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="3" fill="#f5f8fb" stroke="#35465e" stroke-width="2"/><path d="M{x},{y+40} H{x+w}" stroke="#35465e"/>')
        self.text(x+w/2,y+27,title,20,'middle',True)
        for i,t in enumerate(lines):self.text(x+12,y+65+i*25,t,18)
        if methods:
            yy=y+55+len(lines)*25
            self.parts.append(f'<path d="M{x},{yy} H{x+w}" stroke="#35465e"/>')
            for i,t in enumerate(methods):self.text(x+12,yy+25+i*25,t,18)
        label='<b>'+html.escape(title)+'</b><hr>'+'<br>'.join(map(html.escape,lines))
        if methods:label+='<hr>'+'<br>'.join(map(html.escape,methods))
        cell=ET.SubElement(self.root,'mxCell',id=key,value=label,style='rounded=0;whiteSpace=wrap;html=1;fillColor=#f5f8fb;strokeColor=#35465e;fontSize=18;align=left;spacing=10;',vertex='1',parent='1')
        ET.SubElement(cell,'mxGeometry',x=str(x),y=str(y),width=str(w),height=str(h),attrib={'as':'geometry'})
    def line(self,points,source=None,target=None,kind='plain',label=''):
        path=' '.join(('M' if i==0 else 'L')+f'{x},{y}' for i,(x,y) in enumerate(points))
        self.parts.append(f'<path d="{path}" fill="none" stroke="#35465e" stroke-width="2.4"/>')
        self.i+=1
        if source and target:
            style='edgeStyle=orthogonalEdgeStyle;rounded=0;html=1;strokeColor=#35465e;fontSize=17;'
            style+=('endArrow=block;endFill=0;' if kind=='inherit' else 'startArrow=diamond;startFill=1;endArrow=none;' if kind=='compose' else 'endArrow=none;')
            cell=ET.SubElement(self.root,'mxCell',id='e'+str(self.i),value=label,style=style,edge='1',parent='1',source=source,target=target)
            ET.SubElement(cell,'mxGeometry',relative='1',attrib={'as':'geometry'})
    def triangle(self,x,y):self.parts.append(f'<path d="M{x},{y} L{x-10},{y+18} L{x+10},{y+18} Z" fill="white" stroke="#35465e" stroke-width="2"/>')
    def diamond(self,x,y,horizontal=True):
        pts=f'{x},{y} {x+12},{y-7} {x+24},{y} {x+12},{y+7}'
        self.parts.append(f'<polygon points="{pts}" fill="#35465e"/>')
    def arrow(self,x,y):self.parts.append(f'<path d="M{x-8},{y-12} L{x},{y} L{x+8},{y-12}" fill="none" stroke="#35465e" stroke-width="2.4"/>')
    def save(self,name):
        (OUT/(name+'.svg')).write_text(''.join(self.parts)+'</svg>',encoding='utf-8')
        ET.indent(self.model);ET.ElementTree(self.model).write(OUT/(name+'.drawio'),encoding='utf-8',xml_declaration=True)

def main():
    d=Diagram(1140,760)
    d.box('features',15,35,270,170,'PropertyFeatures',['property_id: bigint','features: jsonb'],['setFencedYard(bool)'])
    d.box('property',355,35,390,195,'Property',['property_id: bigint','address, type, beds, area'],['summary(): text','setFencedYard(bool): jsonb'])
    d.box('listing',825,35,270,170,'Listing',['listing_id: bigint','property_id: bigint','price, status'])
    d.line([(285,120),(355,120)],'property','features','compose','1 owns 0..1');d.diamond(331,120)
    d.text(290,105,'0..1',17);d.text(337,145,'1',17)
    d.line([(745,120),(825,120)],'property','listing',label='1 has 0..*')
    d.text(756,106,'1',17);d.text(787,106,'0..*',17)
    children=[('detached',15,'DetachedProperty',['lot_area_sqm: numeric']),('condo',300,'CondoProperty',['floor_number: smallint','monthly_condo_fee: numeric']),('townhouse',585,'TownhouseProperty',['shared_walls: smallint']),('other',870,'OtherProperty',['category_note: text'])]
    for key,x,title,lines in children:
        d.box(key,x,335,250,130,title,lines)
        d.line([(x+125,335),(x+125,280),(550,280),(550,248)],key,'property','inherit')
    d.line([(550,248),(550,230)]);d.triangle(550,230)
    d.text(550,505,'Complete and disjoint by property_type',18,'middle')
    d.box('document',365,565,450,165,'ListingDocument',['document_id, listing_id: bigint','topic, title, body: text','embedding: vector(384)'])
    d.line([(1095,125),(1127,125),(1127,645),(815,645)],'listing','document','compose','1 owns 0..*')
    d.diamond(1095,125);d.text(1104,109,'1',17);d.text(835,630,'0..*',17)
    d.text(365,540,'Superclass fields are stored once in tre.property.',19)
    d.save('UML_Class_Diagram')
    p=Diagram(1140,720)
    p.box('source',25,25,495,125,'Source and key links',['Phase 2: 200 properties and 250 listings','Local generator: 10 topic documents per listing'])
    p.box('json',640,25,475,125,'Property feature generation',['Nested objects and amenity array','Same fictional facts used in source text'])
    p.box('audit',25,205,495,125,'Clean and review 2500 text rows',['Check blanks, duplicates, keys and token length','Keep raw text and record SHA256 hashes'])
    p.box('features',640,205,475,125,'PostgreSQL JSONB',['200 property feature rows; CHECK constraints','Amenity lookup, controlled update function'])
    p.box('model',25,385,495,125,'Embed locally on CPU',['all-MiniLM-L6-v2; pinned revision','384 dimensions; mean pooling; normalize'])
    p.box('load',640,385,475,125,'Load into PostgreSQL 18',['Documents linked by bigint listing_id','Store vector, model revision and source hash'])
    p.box('index',25,565,495,125,'Build indexes',['HNSW cosine for vectors; GIN for JSONB','GIN tsvector for full text search'])
    p.box('query',640,565,475,125,'Query and evaluate',['OO hierarchy + JSONB + vector similarity','Top 5 labels; hybrid search; index comparison'])
    for x,y1,y2,a,b in [(272,150,205,'source','audit'),(877,150,205,'json','features'),(272,330,385,'audit','model'),(877,510,565,'load','query')]:
        p.line([(x,y1),(x,y2)],a,b);p.arrow(x,y2)
    p.line([(520,448),(640,448)],'model','load');p.text(550,432,'SQL',18)
    p.line([(640,485),(570,485),(570,550),(272,550),(272,565)],'load','index');p.arrow(272,565)
    p.line([(520,625),(640,625)],'index','query');p.text(545,610,'plans',18)
    p.line([(1115,270),(1130,270),(1130,625),(1115,625)],'features','query')
    p.save('Data_Pipeline_Diagram')

if __name__=='__main__':main()
