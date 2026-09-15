"""Register current ordinary-input stage captures as identity-specific covers."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'InheritanceTasks/Art/Pixel/v3'
IDS=['travel','life','business','food','adventure','magic']

def update(task,source_dir):
    folder,task_id={'dong':('dong','dong_yong_chuanshuo'),'paper':('paper','ezhou_diaohua_jianzhi')}[task]
    records=[]
    for name in IDS:
        filename=f'dong-{name}_blogger.png' if task=='dong' else f'{name}_blogger-ready.png'
        source=ROOT/source_dir/filename
        assert Image.open(source).size==(1000,600),source
        target=BASE/'runtime'/folder/f'cover-{name}.png'
        shutil.copyfile(source,target)
        records.append({'avatar':name+'_blogger','source':source.relative_to(ROOT).as_posix(),
                        'runtime':target.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(target.read_bytes()).hexdigest()})
    shutil.copyfile(BASE/'runtime'/folder/'cover-travel.png',BASE/'runtime'/folder/'cover.png')
    path=BASE/'resources'/f'{task_id}.tres'
    text=path.read_text(encoding='utf-8')
    text=re.sub(r'^\[ext_resource[^\n]+id="identity_cover_[^\n]+\]\n*','',text,flags=re.M)
    text=re.sub(r'^avatar_covers = [^\n]+\n*','',text,flags=re.M)
    entries='\n\n'.join(f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{folder}/cover-{name}.png" id="identity_cover_{name}"]' for name in IDS)
    first=text.index('[sub_resource')
    text=text[:first]+entries+'\n\n'+text[first:]
    text+='\navatar_covers = {'+', '.join(f'&"{name}_blogger": ExtResource("identity_cover_{name}")' for name in IDS)+'}\n'
    if task=='paper':text=text.replace('v3/action-art-manifest.json','v3/paper-detail-manifest.json')
    path.write_text(text,encoding='utf-8')
    (BASE/'source'/folder/'identity-covers.json').write_text(json.dumps({
        'method':'Unmodified ordinary-input Godot captures; separate cover for each chosen blogger',
        'user_acceptance':False,'covers':records},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(task,': six identity covers registered; source captures untouched')

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('task',choices=['dong','paper'])
    parser.add_argument('source_dir')
    args=parser.parse_args()
    update(args.task,args.source_dir)
