"""Normalize approved-direction imagegen sources without drawing new artwork.

Originals stay untouched. Alchemy exports retain their original colors and
400px cells; technical background removal and layout decisions are recorded.
"""
from pathlib import Path
import hashlib
import json
import shutil
import math
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
V3 = ROOT / 'InheritanceTasks/Art/Pixel/v3'
R4 = ROOT / 'InheritanceTasks/Art/Pixel/v2/review/generated-motion-r4'
OUT = V3 / 'runtime/xia_lian_dan_shu'
IDS = ['travel', 'life', 'business', 'food', 'adventure', 'magic']
DURATIONS = [.15, .13, .17, .12, .09, .10, .14, .16]

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def palette_rgba(im, colors):
    rgba = im.convert('RGBA')
    alpha = rgba.getchannel('A')
    # Transparent technical green must not occupy a color in the fitted palette.
    rgb = Image.new('RGB', rgba.size, '#514652')
    rgb.paste(rgba.convert('RGB'), mask=alpha)
    quantized = rgb.quantize(colors=colors, dither=Image.Dither.NONE).convert('RGBA')
    quantized.putalpha(alpha)
    return quantized

def matte(im):
    rgba = im.convert('RGBA')
    pixels = list(rgba.getdata())
    removed = 0
    for i, (r,g,b,a) in enumerate(pixels):
        if g > r+18 and g > b+18:
            pixels[i] = (0,0,0,0)
            removed += 1
        elif g > max(r,b)+4:
            pixels[i] = (r,max(r,b)+4,b,a)
    rgba.putdata(pixels)
    return rgba, removed

def save(im, name):
    path = OUT / name
    im.save(path)
    colors = len(set(p[:3] for p in im.convert('RGBA').getdata() if p[3]))
    return {'file': str(path.relative_to(ROOT)).replace('\\','/'),
            'sha256': sha(path), 'size': list(im.size), 'opaque_colors': colors}

def composite_cover(plate, rigid, atlas):
    cover=plate.copy()
    cell=atlas.crop((0,0,400,400))
    alpha=cell.getchannel('A')
    edge=[]
    for y in range(204,264):
        xs=[x for x in range(164,390) if alpha.getpixel((x,y))>0]
        if xs:edge.append((max(xs),y))
    far=max(x for x,y in edge)
    ys=[y for x,y in edge if x>=far-1]
    start=(180+far,172+round(sum(ys)/len(ys)))
    end=(486,404)
    if start[0]<end[0]:
        # Same generated shaft and contact positions as the in-engine layer.
        length=math.hypot(end[0]-start[0],end[1]-start[1])
        angle=math.degrees(math.atan2(end[1]-start[1],end[0]-start[0]))
        shaft=Image.open(OUT/'shaft.png').resize((round(length)+10,12),Image.Resampling.NEAREST)
        shaft=shaft.rotate(-angle,resample=Image.Resampling.NEAREST,expand=True)
        center=((start[0]+end[0])/2,(start[1]+end[1])/2)
        cover.alpha_composite(shaft,(round(center[0]-shaft.width/2),round(center[1]-shaft.height/2)))
    cover.alpha_composite(rigid)
    cover.alpha_composite(cell,(180,172))
    return cover

def make_actor(source, name):
    original = Image.open(source)
    cleaned, removed = matte(original)
    atlas = Image.new('RGBA', (4800,400))
    offsets = []
    for i in range(8):
        col, row = i%4, i//4
        bounds = (round(col*cleaned.width/4),round(row*cleaned.height/2),
                  round((col+1)*cleaned.width/4),round((row+1)*cleaned.height/2))
        frame = cleaned.crop(bounds).resize((400,400),Image.Resampling.NEAREST)
        bbox = frame.getbbox()
        dy = 384-bbox[3] if bbox else 0
        # Only common ground-line registration; no per-frame scale or body warp.
        registered = Image.new('RGBA',(400,400))
        registered.alpha_composite(frame,(0,dy))
        atlas.alpha_composite(registered,(i*400,0))
        offsets.append(dy)
    reactions=V3/'source/alchemy'/f'{name}-reactions.png'
    if reactions.exists():
        sheet,_=matte(Image.open(reactions))
        first=sheet.crop((0,0,round(sheet.width/4),sheet.height))
        source_box=first.getbbox();target_frame=atlas.crop((0,0,400,400));target_box=target_frame.getbbox()
        scale=(target_box[3]-target_box[1])/(source_box[3]-source_box[1])
        def foot_center(im,box):
            lower=im.crop((0,box[3]-round((box[3]-box[1])*.08),im.width,box[3])).getbbox()
            return (lower[0]+lower[2])/2
        dx=round(foot_center(target_frame,target_box)-foot_center(first,source_box)*scale)
        dy=round(target_box[3]-source_box[3]*scale)
        for col in range(4):
            cell=sheet.crop((round(col*sheet.width/4),0,round((col+1)*sheet.width/4),sheet.height))
            # A reaction sheet can have nonsquare cells. Preserve aspect and
            # register the whole sequence to the existing actor's foot anchor.
            frame=cell.resize((round(cell.width*scale),round(cell.height*scale)),Image.Resampling.NEAREST)
            registered=Image.new('RGBA',(400,400));registered.alpha_composite(frame,(dx,dy))
            atlas.alpha_composite(registered,((8+col)*400,0))
    else:
        for col in range(4): atlas.alpha_composite(atlas.crop((0,0,400,400)),((8+col)*400,0))
    item = save(atlas,name+'.png')
    item.update(source=str(source.relative_to(ROOT)).replace('\\','/'), source_sha256=sha(source),
                technical_matte_pixels=removed, original_mode=original.mode,
                frame_size=[400,400], frame_count=12, frame_durations=DURATIONS, color_reduction=False,
                ground_registration_y=offsets, native_alpha=original.mode=='RGBA',
                status='generated candidate; actual playback review required')
    return item, atlas

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    (V3/'resources').mkdir(exist_ok=True)
    records=[]
    plate=Image.open(R4/'workshop-clean-plate.png').convert('RGBA').resize((1000,600),Image.Resampling.NEAREST)
    records.append(save(plate,'background.png'))
    # Fixed vessel restores the occlusion in front of the independently animated fire.
    mask=Image.new('L',(500,300))
    ImageDraw.Draw(mask).polygon([(341,174),(348,173),(349,166),(365,161),(368,156),(379,156),(380,161),(393,165),(398,169),(397,173),(404,174),(405,181),(399,186),(397,193),(393,200),(382,203),(362,202),(353,199),(349,191),(347,185),(342,183)],fill=255)
    pot=plate.copy(); pot.putalpha(mask.resize((1000,600),Image.Resampling.NEAREST))
    records.append(save(pot,'vessel-occlusion.png'))
    box,_=matte(Image.open(R4/'pump-cycle-matte.png'))
    rigid=Image.new('RGBA',(1000,600))
    for sx,sy,sw,sh in [(194,232,249,18),(201,250,242,28),(185,278,258,149)]:
        part=box.crop((sx,sy,sx+sw,sy+sh)).resize((round(sw*.9),round(sh*.9)),Image.Resampling.NEAREST)
        rigid.alpha_composite(part,(round(180+(sx+110)*.9),round(172+sy*.9)))
    records.append(save(rigid,'bellows-fixed.png'))
    records.append(save(box.crop((76,255,91,270)),'shaft.png'))
    fire=Image.open(R4/'fire-sheet.png').convert('RGB')
    flames=Image.new('RGBA',(4*154,3*154))
    for row,top in enumerate([23,348,685]):
        for col,sx in enumerate([41,403,765,1127]):
            cell=fire.crop((sx,top,sx+280,top+280)).resize((154,154),Image.Resampling.NEAREST).convert('RGBA')
            data=[]
            for r,g,b,a in cell.getdata():
                strength=max(r,g,b)
                data.append((min(255,round(r*255/max(1,strength))),min(255,round(g*255/max(1,strength))),min(255,round(b*255/max(1,strength))),strength if strength>8 else 0))
            cell.putdata(data)
            flames.alpha_composite(cell,(col*154,row*154))
    records.append(save(flames,'fire.png'))
    actors={}
    for name in IDS:
        source=R4/'character-handle-sheet.png' if name=='travel' else V3/'source/alchemy'/f'{name}-pump.png'
        if name == 'food' and (V3/'source/alchemy/food-pump-r2.png').exists():
            source=V3/'source/alchemy/food-pump-r2.png'
        if source.exists():
            item,atlas=make_actor(source,name);records.append(item);actors[name]=atlas
            cover=composite_cover(plate,rigid,atlas)
            records.append(save(cover,f'cover-{name}.png'))
    write_resource(actors)
    manifest={'schema_version':3,'method':'built-in imagegen; deterministic slicing and technical alpha cleanup; original colors, 400px actor cells, 1000x600 stage',
              'date':'2026-09-14','character_direction':'r4 travel face/proportion retained by user; motion still under review',
              'source_manifest':str((R4/'manifest.json').relative_to(ROOT)).replace('\\','/'),
              'culture':'Game-designed medicinal workshop, not a reconstruction of documented Xia equipment.',
              'runtime':records,'available_characters':list(actors),'not_user_accepted_as_complete':True}
    (V3/'alchemy-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'assets':len(records),'characters':list(actors),'output':str(OUT)},ensure_ascii=False))

def write_resource(actors):
    # Keep missing identities explicit in the fallback resource; never substitute travel.
    text=['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]',
          '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="script"]',
          '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="appearance"]',
          '[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/xia_lian_dan_shu_pixel.tscn" id="stage"]',
          '[ext_resource type="Resource" path="res://InheritanceTasks/Art/Pixel/v2/resources/xia_lian_dan_shu.tres" id="previous"]',
          '[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/xia_lian_dan_shu/background.png" id="background"]']
    for name in actors:
        text += [f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/xia_lian_dan_shu/{name}.png" id="{name}"]',
                 f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/xia_lian_dan_shu/cover-{name}.png" id="cover_{name}"]']
    for name in actors:
        for i in range(12):
            text += [f'[sub_resource type="AtlasTexture" id="{name}_{i}"]',f'atlas = ExtResource("{name}")',f'region = Rect2({i*400}, 0, 400, 400)','filter_clip = true']
        entries=[]
        for action,indices,loop,speed in [('ready',[10],False,1),('prepare',[10,0],False,4),('action',list(range(8)),True,1),('hold',list(range(8)),True,1),('release',[7,9,10],False,6),('miss',[8],False,1),('recover',[9,10],False,4),('success',[10,11],False,3)]:
            frames=', '.join('{"duration": %s, "texture": SubResource("%s_%d")}'%(DURATIONS[i] if loop else 1.0,name,i) for i in indices)
            entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(frames,str(loop).lower(),action,speed))
        text += [f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(entries)+']',f'[sub_resource type="Resource" id="avatar_{name}"]','script = ExtResource("appearance")',f'avatar_id = &"{name}_blogger"','costume_id = &"xia_lian_dan_shu"',f'portrait = SubResource("{name}_0")',f'sprite_frames = SubResource("frames_{name}")',f'atlas = ExtResource("{name}")','frame_size = Vector2i(400, 400)','anchors = {&"feet": Vector2(148, 384), &"grip": Vector2(192, 236)}','reference_note = "直接生成：以原博主为身份参考，保留原色与400像素帧细节；炼药装束和风箱为游戏化设计。"']
    appearances=', '.join(f'&"{n}_blogger": SubResource("avatar_{n}")' for n in actors)
    covers=', '.join(f'&"{n}_blogger": ExtResource("cover_{n}")' for n in actors)
    rod_maps=[]
    for name,atlas in actors.items():
        points=[]
        for i in range(12):
            cell=atlas.crop((i*400,0,(i+1)*400,400));a=cell.getchannel('A')
            rows=[]
            for y in range(204,264):
                xs=[x for x in range(164,390) if a.getpixel((x,y))>0]
                if xs:rows.append((max(xs),y))
            far=max(x for x,y in rows)
            ys=[y for x,y in rows if x>=far-1]
            points.append(f'Vector2({far/2},{round(sum(ys)/len(ys))/2})')
        rod_maps.append(f'&"{name}_blogger": ['+', '.join(points)+']')
    rod_property='"rod_anchors": {'+', '.join(rod_maps)+'}, '
    text += ['[resource]','script = ExtResource("script")','version = 3','stage_scene = ExtResource("stage")','background = ExtResource("background")','cover = ExtResource("cover_travel")',f'avatar_appearances = {{{appearances}}}',f'avatar_covers = {{{covers}}}','properties = {"generated_workshop": true, "fallback_presentation": ExtResource("previous"), "native_pixel_scale": 2, "status": "生成动作接入，待逐角色画面验收"}','source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/alchemy-manifest.json"']
    output='\n\n'.join(text)+'\n'
    output=output.replace('properties = {','properties = {'+rod_property)
    output=output.replace('version = 3','version = 3\npixel_canvas_size = Vector2i(1000,600)')
    output=output.replace('"native_pixel_scale": 2','"native_pixel_scale": 1')
    (V3/'resources/xia_lian_dan_shu.tres').write_text(output,encoding='utf-8')

if __name__=='__main__':
    build()
