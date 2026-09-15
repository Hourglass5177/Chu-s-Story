"""Slice generated sugar art without reducing source-frame detail or colors."""
from pathlib import Path
import hashlib, json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
V3 = ROOT / 'InheritanceTasks/Art/Pixel/v3'
SRC = V3 / 'source/sugar'
OUT = V3 / 'runtime/tianmen_tang_su'
IDS = ['travel','life','business','food','adventure','magic']
FRAME = 362
BUBBLE_FRAME = 362
ANIMATIONS = {
    'ready': ([7,7,1], [.7,.7,.22], True),
    'prepare': ([1,2], [.24,.12], False),
    'hold': ([2,3,4,3], [.16,.18,.2,.18], True),
    'release': ([5,6,7], [.15,.25,.35], False),
    'miss': ([8,7], [.8,.35], False),
    'over': ([10,8,7], [.35,.45,.35], False),
    'recover': ([9,7], [.8,.35], False),
    'success': ([9,9], [.6,.6], False),
}

def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()

def matte(im):
    result = im.convert('RGBA')
    pixels=[]
    for r,g,b,a in result.getdata():
        if g > r+18 and g > b+18: pixels.append((0,0,0,0))
        else: pixels.append((r,min(g,max(r,b)+4),b,a))
    result.putdata(pixels)
    return result

def save(im,name):
    path=OUT/name; im.save(path)
    return {'file':path.relative_to(ROOT).as_posix(),'sha256':sha(path),'size':list(im.size),
            'opaque_colors':len(set(c[:3] for c in im.convert('RGBA').getdata() if c[3]))}

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    plate=Image.open(SRC/'background-clean.png').convert('RGBA').resize((1000,600),Image.Resampling.NEAREST)
    records=[save(plate,'background.png')]
    foreground=Image.new('RGBA',plate.size)
    foreground.alpha_composite(plate.crop((0,486,1000,600)),(0,486))
    records.append(save(foreground,'foreground.png'))
    actors={}
    for name in IDS:
        source=SRC/(f'{name}-strip-r2.png' if name in ['travel','food'] else f'{name}-strip.png')
        original=Image.open(source)
        cleaned=matte(original)
        atlas=Image.new('RGBA',(12*FRAME,FRAME))
        offsets=[]
        for i in range(12):
            col,row=i%4,i//4
            bounds=(col*362,row*362,(col+1)*362,(row+1)*362)
            frame=cleaned.crop(bounds)
            # Preserve the 362px source square; only translate the whole frame.
            # The rightmost tube lip provides a common contact registration.
            candidates=[(x,y) for y in range(174,236) for x in range(317,FRAME) if frame.getpixel((x,y))[3] > 0]
            tip_x=max(x for x,y in candidates)
            tip_ys=[y for x,y in candidates if x>=tip_x-1]
            tip_y=round((min(tip_ys)+max(tip_ys))/2)
            shift=(355-tip_x,214-tip_y)
            registered=Image.new('RGBA',(FRAME,FRAME)); registered.alpha_composite(frame,shift)
            atlas.alpha_composite(registered,(i*FRAME,0)); offsets.append(list(shift))
        record=save(atlas,name+'.png')
        record.update(source=source.relative_to(ROOT).as_posix(),source_sha256=sha(source),
                      original_mode=original.mode,native_alpha=False,technical_green_removed=True,
                      frame_size=[FRAME,FRAME],frame_count=12,tip=[355,214],translation_registration=offsets,
                      original_identity=f'arts/素材合集/sprite及立绘/Sprite/角色/{dict(zip(IDS,["旅行博主","生活博主","商业博主","美食博主","探险博主","魔术博主"]))[name]}.png')
        records.append(record); actors[name]=atlas
    raw=Image.open(SRC/'bubbles.png').convert('RGBA')
    bubbles=Image.new('RGBA',(6*BUBBLE_FRAME,BUBBLE_FRAME))
    # Imagegen supplied real alpha for these six membranes; preserve it.
    # Equal central square crops remove the unused top and bottom margins.
    for i in range(6):
        tile=raw.crop((i*362,181,(i+1)*362,543))
        bubbles.alpha_composite(tile,(i*BUBBLE_FRAME,0))
    records.append(save(bubbles,'bubbles.png'))
    for name,atlas in actors.items():
        cover=plate.copy(); cover.alpha_composite(atlas.crop((7*FRAME,0,8*FRAME,FRAME)).resize((400,400),Image.Resampling.NEAREST),(70,90))
        cover.alpha_composite(bubbles.crop((5*BUBBLE_FRAME,0,6*BUBBLE_FRAME,BUBBLE_FRAME)).resize((224,224),Image.Resampling.NEAREST),(478,218))
        cover.alpha_composite(foreground); records.append(save(cover,'cover-'+name+'.png'))
    write_resource()
    manifest={'schema_version':4,'date':'2026-09-14','method':'built-in imagegen; full-resolution source-frame slicing, technical-matte removal and translation registration only; no palette quantization',
              'native_canvas':[1000,600],'logical_scale':1,'actor_native_rect':[70,90,400,400],
              'source_frame_size':[FRAME,FRAME],'palette_reduction':False,
              'tube_tip_native':[462,326],'bubble_center_native':[590,330],'animations':ANIMATIONS,
              'reference_roles':{'original_bloggers':'identity only','sugar/keyframe-travel.png':'scene, costume and proportion','travel-strip-r2.png':'whole-strip pose and timing template'},
              'culture':'Generated temple-fair sugar stall and blowing gestures are game art, not documented process parameters.',
              'status':'generated candidates; runtime visual/playback audit recorded separately; not user accepted',
              'runtime':records,'source_files':[{'file':p.relative_to(ROOT).as_posix(),'sha256':sha(p)} for p in sorted(SRC.iterdir()) if p.is_file()]}
    (V3/'sugar-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'assets':len(records),'characters':IDS,'output':str(OUT)},ensure_ascii=False))

def write_resource():
    t=['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]',
       '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="script"]',
       '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="appearance"]',
       '[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/tianmen_tang_su_pixel.tscn" id="stage"]']
    for name in ['background','foreground']+IDS+['cover-'+n for n in IDS]:
        t += [f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/tianmen_tang_su/{name}.png" id="{name}"]']
    for name in IDS:
        for i in range(12):
            t += [f'[sub_resource type="AtlasTexture" id="{name}_{i}"]',f'atlas = ExtResource("{name}")',f'region = Rect2({i*FRAME},0,{FRAME},{FRAME})','filter_clip = true']
        entries=[]
        for action,(indices,durations,loop) in ANIMATIONS.items():
            frames=', '.join('{"duration": %s, "texture": SubResource("%s_%d")}'%(duration,name,index) for index,duration in zip(indices,durations))
            entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": 1.0}'%(frames,str(loop).lower(),action))
        t += [f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(entries)+']',
              f'[sub_resource type="Resource" id="avatar_{name}"]','script = ExtResource("appearance")',
              f'avatar_id = &"{name}_blogger"','costume_id = &"tianmen_tang_su"',f'portrait = SubResource("{name}_7")',
              f'sprite_frames = SubResource("frames_{name}")',f'atlas = ExtResource("{name}")',f'frame_size = Vector2i({FRAME},{FRAME})',
              'anchors = {&"tube_tip": Vector2(355,214), &"waist": Vector2(163,358)}',
              'reference_note = "以原博主为身份参考，整条吹气与收气动作直接生成；糖摊装束与操作为游戏化表现。"']
    t += ['[resource]','script = ExtResource("script")','version = 3','pixel_canvas_size = Vector2i(1000,600)','stage_scene = ExtResource("stage")',
          'background = ExtResource("background")','foreground = ExtResource("foreground")','cover = ExtResource("cover-travel")',
          'avatar_appearances = {'+', '.join(f'&"{n}_blogger": SubResource("avatar_{n}")' for n in IDS)+'}',
          'avatar_covers = {'+', '.join(f'&"{n}_blogger": ExtResource("cover-{n}")' for n in IDS)+'}',
          'properties = {"generated_sugar": true, "native_pixel_scale": 1, "bubble_frame_size": 362, "preserve_source_detail": true, "status": "保留原稿细节的生成美术，待用户试玩"}',
          'source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/sugar-manifest.json"']
    (V3/'resources/tianmen_tang_su.tres').write_text('\n\n'.join(t)+'\n',encoding='utf-8')

if __name__=='__main__': build()
