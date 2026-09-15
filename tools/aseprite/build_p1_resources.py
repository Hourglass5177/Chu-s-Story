"""Godot resource wiring for the two reviewed-sample candidates, never all 15."""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v2'
IDS = ['travel', 'life', 'business', 'food', 'adventure', 'magic']
PREFIX = 'res://InheritanceTasks/Art/Pixel/v2/'

def build(task, folder, size, actions):
    lines = ['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]', '',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="script"]',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="appearance"]',
        f'[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/{task}_pixel.tscn" id="stage"]',
        f'[ext_resource type="Texture2D" path="{PREFIX}runtime/{folder}/background{("-0" if folder=="shennong" else "")}.png" id="background"]']
    for name in IDS:
        lines.append(f'[ext_resource type="Texture2D" path="{PREFIX}runtime/{folder}/{name}.png" id="{name}"]')
        if folder == 'shennong':
            lines.append(f'[ext_resource type="Texture2D" path="{PREFIX}runtime/alchemy/{name}.png" id="portrait_{name}"]')
    if folder == 'alchemy':
        for name in IDS:
            lines.append(f'[ext_resource type="Texture2D" path="{PREFIX}runtime/alchemy/cover-{name}.png" id="cover_{name}"]')
    lines.append('')
    for name in IDS:
        for frame in range(14):
            lines += [f'[sub_resource type="AtlasTexture" id="{name}_{frame}"]',f'atlas = ExtResource("{name}")',
                f'region = Rect2({frame*size[0]}, 0, {size[0]}, {size[1]})','filter_clip = true','']
        if folder == 'shennong':
            lines += [f'[sub_resource type="AtlasTexture" id="portrait_{name}"]',f'atlas = ExtResource("portrait_{name}")','region = Rect2(0, 0, 96, 128)','filter_clip = true','']
        anims=[]
        for action,(frames,speed,loop) in actions.items():
            refs=', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}'%(name,frame) for frame in frames)
            anims.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(refs,str(loop).lower(),action,float(speed)))
        lines += [f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(anims)+']','',
            f'[sub_resource type="Resource" id="avatar_{name}"]','script = ExtResource("appearance")',
            f'avatar_id = &"{name}_blogger"',f'costume_id = &"{task}"',
            f'portrait = SubResource("{name}_0")' if folder=='alchemy' else f'portrait = SubResource("portrait_{name}")',
            f'sprite_frames = SubResource("frames_{name}")',f'atlas = ExtResource("{name}")',
            f'frame_size = Vector2i({size[0]}, {size[1]})',
            'anchors = {&"feet": Vector2(46, 124), &"grip": Vector2(84, 82)}' if folder=='alchemy' else 'anchors = {&"feet": Vector2(10, 24)}',
            'reference_note = "原博主身份衍生，固定母色板，Aseprite透明分层绘制；主题装束与操作动作是游戏化设计。"','']
    lines += ['[resource]','script = ExtResource("script")','version = 2','stage_scene = ExtResource("stage")',
        'background = ExtResource("background")','cover = ExtResource("cover_travel")' if folder=='alchemy' else 'cover = ExtResource("background")',
        'avatar_appearances = {'+', '.join(f'&"{name}_blogger": SubResource("avatar_{name}")' for name in IDS)+'}',
        'properties = {"palette": "Chu Workshop 48", "native_pixel_scale": 2, "status": "P1 review candidate", "action_clock": "local semantic state"}',
        f'source_manifest_path = "{PREFIX}p1-manifest.json"']
    if folder == 'alchemy':
        lines.append('avatar_covers = {'+', '.join(f'&"{name}_blogger": ExtResource("cover_{name}")' for name in IDS)+'}')
    target=ART/'resources'/f'{task}.tres';target.parent.mkdir(exist_ok=True,parents=True)
    target.write_text('\n'.join(lines)+'\n',encoding='utf-8')
    definition=ROOT/'InheritanceTasks/Definitions'/f'{task}.tres'
    text=definition.read_text(encoding='utf-8')
    text=re.sub(r'path="res://InheritanceTasks/Art/Pixel/v1/resources/[^\"]+" id="pixel_presentation"',
        f'path="{PREFIX}resources/{task}.tres" id="pixel_presentation"',text)
    definition.write_text(text,encoding='utf-8')

build('xia_lian_dan_shu','alchemy',(96,128),{
    'ready':([0],1,False),'prepare':([0],1,False),'action':(list(range(8)),10,True),
    'hold':(list(range(8)),10,True),'release':([8,9],10,False),'miss':([10],1,False),
    'recover':([11],1,False),'success':([12,13],5,False)})
build('yandi_shennong_chuanshuo','shennong',(20,24),{
    'ready':([8],1,False),'idle':([8],1,True),'run':(list(range(8)),11.111,True),
    'jump_short':([9],1,False),'jump_long':([9],1,False),'fall':([10],1,False),
    'land':([11],1,False),'recover':([12],1,False),'gather':([13],1,False)})
(ART/'p1-manifest.json').write_text(json.dumps({
    'version':2,'status':'P1 visual review candidate, not user accepted',
    'native_canvas':[500,300],'logical_canvas':[1000,600],'palette':'palette.json',
    'authoring':'Aseprite indexed layers, tools/aseprite/draw_p1_assets.lua',
    'tasks':['xia_lian_dan_shu','yandi_shennong_chuanshuo'],
    'preserved':'All v1 and original blogger images remain unchanged',
    'animation':'Per-action clocks; nonloop actions hold their last frame',
},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Built two P1 presentation resources.')
