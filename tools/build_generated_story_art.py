"""Slice imagegen story triptychs into nine immutable puzzle pictures."""
from pathlib import Path
import json, hashlib
from PIL import Image
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'InheritanceTasks/Art/Pixel/v3'
def build():
    # Keep the rejected 210px/48-colour exports as history. Runtime v4 uses
    # exact source crops for both puzzle and reference, without resampling.
    out=BASE/'runtime/story-detail-v4';out.mkdir(parents=True,exist_ok=True)
    records=[]
    sources={'water_cow':'https://news.hubeidaily.net/pc/c_2714369.html','tribute_rice':'https://news.hubeidaily.net/mobile/c_2999822.html','dragon_temple':'https://news.hubeidaily.net/pc/c_3216991.html'}
    for name,url in sources.items():
        path=BASE/'source/story'/f'{name}.png'
        im=Image.open(path).convert('RGB')
        if im.size != (2172,724):
            raise ValueError(f'{path}: source layout changed; review crop rectangles first')
        for i in range(3):
            panel=im.crop((round(i*im.width/3),0,round((i+1)*im.width/3),im.height))
            target=out/f'{name}-{i+1}.png';panel.save(target)
            assert Image.open(target).tobytes() == panel.tobytes()
            records.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'size':list(panel.size),'crop':[724*i,0,724*(i+1),724],'source_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'story_source':url,'method':'Exact RGB source crop; no palette reduction, resize or sharpening. Puzzle and reference share this texture.','status':'new generated legend illustration; not a historical reconstruction; awaiting player review'})
    (BASE/'story-detail-v4-manifest.json').write_text(json.dumps({'schema_version':4,'assets':records,'culture':'Original illustrations adapted from local legends; published article images not reused. Water-cow middle panel corrected to walk into cave; dragon flood depicts no casualties.'},ensure_ascii=False,indent=2),encoding='utf-8')
    print('Exported 9 native 724px puzzle/reference images; exact source pixels verified.')
if __name__=='__main__':build()
