"""Point four rebuilt games at generated v3 art; keep rejected resources archived."""
from pathlib import Path
import re
import sys
import hashlib
import json
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
IDS=['travel','life','business','food','adventure','magic']
TASKS={'dong_yong_chuanshuo':'dong','ezhou_diaohua_jianzhi':'paper','xiabaoping_minjian_gushi':'story','xisai_shenzhou_hui':'shenzhou'}

def build_review_covers():
    """Use actual engine frames, not a composition that differs from gameplay."""
    frames={'dong':'dong-travel_blogger.png','paper':'paper-ready.png',
            'story':'story-0-0-play.png','shenzhou':'boat-ready.png'}
    manifest=[]
    manifest_path=V3/'source/action-covers-manifest.json'
    previous=json.loads(manifest_path.read_text(encoding='utf8')) if manifest_path.exists() else []
    for folder,filename in frames.items():
        if '--only-dong' in sys.argv and folder!='dong': continue
        source=ROOT/'artifacts/action-story-v3'/filename
        if folder=='dong' and (ROOT/'artifacts/dong-original-detail-v4'/filename).exists():
            source=ROOT/'artifacts/dong-original-detail-v4'/filename
        if folder=='dong':
            recorded=next((item['source'] for item in previous if item['task']=='dong'),None)
            if recorded and (ROOT/recorded).exists():source=ROOT/recorded
            if '--dong-frame' in sys.argv:
                source=ROOT/sys.argv[sys.argv.index('--dong-frame')+1]
        picture=Image.open(source)
        if picture.size != (1000,600):
            raise ValueError(f'{source}: expected the actual 1000x600 stage capture')
        target=V3/'runtime'/folder/'cover.png'
        if folder=='dong':picture.save(target)
        else:picture.resize((500,300),Image.Resampling.NEAREST).save(target)
        manifest.append({'task':folder,'source':str(source.relative_to(ROOT)),
                         'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),
                         'target':str(target.relative_to(ROOT)),
                         'method':'Actual Godot ordinary-input frame; original 1000x600 retained.' if folder=='dong' else 'Actual Godot ordinary-input frame; exact 2:1 nearest downsample.',
                         'status':'Current playable candidate, not user visual acceptance.'})
    path=manifest_path
    if '--only-dong' in sys.argv and path.exists():
        manifest=[entry for entry in json.loads(path.read_text(encoding='utf8')) if entry['task']!='dong']+manifest
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def build():
    for task,folder in TASKS.items():
        if '--only-dong' in sys.argv and folder!='dong': continue
        background=f'{folder}/background.png'
        if folder=='story': background='story/water_cow-1.png'
        cover=f'{folder}/cover.png'
        if not (V3/'runtime'/cover).exists(): cover=background
        lines=['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]',
          '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="script"]',
          '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="appearance"]',
          f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{background}" id="bg"]',
          f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{cover}" id="cover"]']
        if folder!='story':lines.append(f'[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/{task}_pixel.tscn" id="stage"]')
        for name in IDS:
            # Outdoor identity art is shared only for shore/story audience appearances.
            path=f'dong/{name}_blogger/reference.png' if folder=='dong' else f'xingshan_min_ge/{name}.png'
            lines.append(f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{path}" id="{name}"]')
            identity_cover=V3/'runtime'/folder/f'cover-{name}.png'
            if folder in ('dong','paper') and identity_cover.exists():
                lines.append(f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{folder}/cover-{name}.png" id="identity_cover_{name}"]')
            if folder=='paper':lines.append(f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/dong/{name}_blogger/head.png" id="portrait_{name}"]')
        for name in IDS:
            if folder=='dong':
                w,h=Image.open(V3/'runtime/dong'/f'{name}_blogger/reference.png').size
                columns=1
            else:
                atlas_size=Image.open(V3/'runtime/xingshan_min_ge'/f'{name}.png').size
                w,h,columns=atlas_size[0]//2,atlas_size[1],2
            for col in range(columns):lines.extend([f'[sub_resource type="AtlasTexture" id="{name}_{col}"]',f'atlas = ExtResource("{name}")',f'region = Rect2({w*col},0,{w},{h})','filter_clip = true'])
            animations=[]
            for action,frame in [('ready',0),('idle',0),('wave',columns-1)]:
                animations.append('{"frames": [{"duration": 1.0, "texture": SubResource("%s_%d")}], "loop": false, "name": &"%s", "speed": 1.0}'%(name,frame,action))
            portrait=f'ExtResource("portrait_{name}")' if folder=='paper' else f'SubResource("{name}_0")'
            lines.extend([f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(animations)+']',f'[sub_resource type="Resource" id="appearance_{name}"]','script = ExtResource("appearance")',f'avatar_id = &"{name}_blogger"',f'costume_id = &"{task}"',f'portrait = {portrait}',f'atlas = ExtResource("{name}")',f'sprite_frames = SubResource("frames_{name}")',f'frame_size = Vector2i({w},{h})',f'anchors = {{&"feet": Vector2({w/2},{h})}}','reference_note = "原博主身份的生成衍生。此 SpriteFrames 仅含准备／岸边静态姿势；董永保留完整生成上身与弯肘姿势，站位及车把联合求解，双腿独立落地，剪纸由刀手组件驱动。故事会与岸边共享乡村体验服，文化人物独立。"'])
        lines.extend(['[resource]','script = ExtResource("script")','version = 3','background = ExtResource("bg")','cover = ExtResource("cover")','avatar_appearances = {'+', '.join(f'&"{n}_blogger": SubResource("appearance_{n}")' for n in IDS)+'}','source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/action-art-manifest.json"','properties = {"native_pixel_scale": 2, "status": "generated candidate; actual scene review and user acceptance recorded separately"}'])
        if folder!='story':lines.append('stage_scene = ExtResource("stage")')
        else:lines[-1]='properties = {"painter": "story", "native_pixel_scale": 2, "status": "generated puzzle imagery; direct logical board renderer"}'
        if folder=='dong' or (folder=='paper' and (V3/'runtime/paper/detail-anchors.json').exists()):
            lines.append('pixel_canvas_size = Vector2i(1000, 600)')
            lines=[line for line in lines if not line.startswith('properties = ')]
            lines.append('properties = {"native_pixel_scale": 1, "source_detail": "Full original RGBA crops retained, no palette reduction or low-resolution export", "status": "generated candidate; visual review and user acceptance remain separate"}')
            if folder=='paper':
                lines=[line.replace('v3/action-art-manifest.json','v3/paper-detail-manifest.json') for line in lines]
        if folder=='shenzhou':
            lines.append('pixel_canvas_size = Vector2i(1000,600)')
        identity_covers=[name for name in IDS if (V3/'runtime'/folder/f'cover-{name}.png').exists()]
        if folder in ('dong','paper') and identity_covers:
            lines.append('avatar_covers = {'+', '.join(f'&"{name}_blogger": ExtResource("identity_cover_{name}")' for name in identity_covers)+'}')
        (V3/'resources'/f'{task}.tres').write_text('\n\n'.join(lines)+'\n',encoding='utf8')
        definition=ROOT/'InheritanceTasks/Definitions'/f'{task}.tres'
        text=definition.read_text(encoding='utf8')
        text=re.sub(r'Art/Pixel/v\d+/resources/'+task+r'\.tres','Art/Pixel/v3/resources/'+task+'.tres',text)
        definition.write_text(text,encoding='utf8')

if __name__=='__main__':
    if '--review-covers' in sys.argv:
        build_review_covers()
        if '--covers-only' in sys.argv:sys.exit(0)
    build()
