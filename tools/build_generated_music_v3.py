"""Normalize imagegen music assets. No drawing; sources and rejected takes stay intact."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
V3 = ROOT / 'InheritanceTasks/Art/Pixel/v3'
IDS = ['travel', 'life', 'business', 'food', 'adventure', 'magic']

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def palette(image, colors):
    alpha = image.getchannel('A')
    base = Image.new('RGB', image.size, '#363944')
    base.paste(image, mask=alpha)
    result = base.quantize(colors=colors, dither=Image.Dither.NONE).convert('RGBA')
    result.putalpha(alpha)
    return result

def technical_matte(image):
    result = image.convert('RGBA')
    if image.mode == 'RGBA' and image.getchannel('A').getextrema()[0] < 255:
        return result
    data = []
    for r, g, b, a in result.getdata():
        if g > 100 and g > max(r,b) + 45:
            data.append((0,0,0,0))
        else:
            data.append((r,g,b,a))
    result.putdata(data)
    return result

def strip(source, columns, rows, size=None, colors=None):
    original = Image.open(source)
    clean = technical_matte(original)
    size = (clean.width//columns,clean.height//rows)
    atlas = Image.new('RGBA',(size[0]*columns*rows,size[1]))
    for i in range(columns*rows):
        x,y=i%columns,i//columns
        bounds=(round(x*clean.width/columns),round(y*clean.height/rows),round((x+1)*clean.width/columns),round((y+1)*clean.height/rows))
        cell=clean.crop((bounds[0],bounds[1],bounds[0]+size[0],bounds[1]+size[1]))
        atlas.alpha_composite(cell,(i*size[0],0))
    return atlas

def animation_spec(task):
    if task=='laohekou_si_xian':
        return {'ready':([0],False,1),'prepare':([1],False,1),'pluck':([2,3,0],False,10),'pluck_recover':([3,0],False,10),'miss':([2,3,0],False,10),'recover':([3,0],False,8),'success':([0],False,1)}
    return {'ready':([0],False,1),'prepare_left':([1],False,1),'prepare_right':([5],False,1),'step_left':([2,3,0],False,8),'step_right':([6,7,0],False,8),'step_recover':([0],False,1),'rest':([0],False,1),'miss':([0],False,1),'recover':([0],False,1),'success':([0],False,1)}

def write_resource(task, actors, size, count):
    previous=(ROOT/'InheritanceTasks/Art/Pixel/v1/resources'/f'{task}.tres').read_text(encoding='utf-8')
    previous=previous.replace(f'v1/runtime/{task}-background.png',f'v3/runtime/{task}/background.png')
    previous=previous.replace(f'v1/runtime/covers/{task}.png',f'v3/runtime/{task}/cover-travel.png')
    insert=[]; sub=[]
    for name in actors:
        insert.append(f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{task}/{name}.png" id="v3_{name}"]')
        for i in range(count):
            sub += [f'[sub_resource type="AtlasTexture" id="v3_{name}_{i}"]',f'atlas = ExtResource("v3_{name}")',f'region = Rect2({i*size[0]}, 0, {size[0]}, {size[1]})','filter_clip = true']
        entries=[]
        for action,(indices,loop,speed) in animation_spec(task).items():
            frames=', '.join('{"duration": 1.0, "texture": SubResource("v3_%s_%d")}'%(name,i) for i in indices)
            entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(frames,str(loop).lower(),action,speed))
        sub += [f'[sub_resource type="SpriteFrames" id="v3_frames_{name}"]','animations = ['+',\n'.join(entries)+']',f'[sub_resource type="Resource" id="v3_avatar_{name}"]','script = ExtResource("2")',f'avatar_id = &"{name}_blogger"',f'costume_id = &"{task}"',f'portrait = SubResource("v3_{name}_0")',f'sprite_frames = SubResource("v3_frames_{name}")',f'atlas = ExtResource("v3_{name}")',f'frame_size = Vector2i({size[0]}, {size[1]})','reference_note = "直接生成候选；原博主身份参考；整条动作统一切片与色板。传统动作仍待资料核对，未获用户美术验收。"']
        previous=previous.replace(f'&"{name}_blogger": SubResource("avatar_{name}")',f'&"{name}_blogger": SubResource("v3_avatar_{name}")')
    index=previous.index('[sub_resource')
    previous=previous[:index]+'\n'.join(insert)+'\n\n'+previous[index:]
    previous=previous.replace('[resource]','\n'.join(sub)+'\n\n[resource]\nversion = 3',1)
    previous=re.sub(r'^properties = .*$', 'properties = {"generated_music": true, "available_generated_avatars": '+json.dumps(actors)+', "art_status": "本轮生成动作候选；其余角色保留原稿等待替换", "chart_review": "游戏编排待听审"}', previous,flags=re.M)
    previous=re.sub(r'^source_manifest_path = .*$',f'source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/{task}-manifest.json"',previous,flags=re.M)
    (V3/'resources'/f'{task}.tres').write_text(previous,encoding='utf-8')

def build_task(task, actor_source, columns, rows, size, npc_source, npc_size):
    source=V3/'source'/task
    out=V3/'runtime'/task;out.mkdir(parents=True,exist_ok=True)
    bg=Image.open(source/'background.png').convert('RGBA').resize((500,300),Image.Resampling.NEAREST)
    bg=palette(bg,48);bg.save(out/'background.png')
    actors=[];records=[]
    for name in IDS:
        file=source/(actor_source if name=='travel' else name+'-animation.png')
        if name=='food' and (source/'food-animation-r2.png').exists():
            file=source/'food-animation-r2.png'
        if not file.exists():continue
        actor=strip(file,columns,rows,size);actor.save(out/(name+'.png'));actors.append(name)
        records.append({'actor':name,'source':file.relative_to(ROOT).as_posix(),'source_sha256':sha(file),'source_mode':Image.open(file).mode,'native_alpha':False,'runtime':(out/(name+'.png')).relative_to(ROOT).as_posix(),'runtime_sha256':sha(out/(name+'.png')),'frame_size':size,'frames':columns*rows,'normal_playback_reviewed':False})
        cover=bg.copy();cover.alpha_composite(actor.crop((0,0,*size)),(192,94) if task=='laohekou_si_xian' else (202,148));cover.save(out/('cover-'+name+'.png'))
    npcs=strip(source/npc_source,4,2,npc_size);npcs.save(out/'npcs.png')
    write_resource(task,actors,size,columns*rows)
    manifest={'method':'imagegen originals; technical matte removal, nearest-neighbour native slicing and one palette for entire strip','status':'generated art candidates; not user accepted','task':task,'background_colors':48,'actor_colors_max':32,'native_canvas':[500,300],'source_identity':'six original blogger illustrations (each generated identity separately referenced)','culture':'Instrument / dance learning scenes simplified from project authorized videos; not exact traditional motion transcription','actors':records,'pending':['complete six blogger identities','normal-speed full-scene visual review','black/white edge review','audition of source phrase boundaries']}
    (V3/(task+'-manifest.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    definition=ROOT/'InheritanceTasks/Definitions'/f'{task}.tres'
    text=definition.read_text(encoding='utf-8').replace(f'v1/resources/{task}.tres',f'v3/resources/{task}.tres')
    definition.write_text(text,encoding='utf-8')
    print(task,actors,size)

if __name__=='__main__':
    # Legacy entry point delegates to the source-resolution-preserving exporter.
    from export_music_v3 import TASKS, build
    for task, spec in TASKS.items(): build(task, spec)
