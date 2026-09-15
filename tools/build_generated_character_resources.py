"""Slice generated sequences without discarding the approved source detail or colors."""
from pathlib import Path
import json
from PIL import Image, ImageOps
from build_generated_pixel_v3 import matte,palette_rgba,sha

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
IDS=['travel','life','business','food','adventure','magic']

def largest_component(im):
    # Remove detached reference birds/technical specks, not character edge colors.
    a=im.getchannel('A');seen=set();best=[]
    for y in range(im.height):
        for x in range(im.width):
            if (x,y) in seen or a.getpixel((x,y))<128: continue
            stack=[(x,y)];seen.add((x,y));points=[]
            while stack:
                q=stack.pop();points.append(q)
                for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
                    p=(q[0]+dx,q[1]+dy)
                    if 0<=p[0]<im.width and 0<=p[1]<im.height and p not in seen and a.getpixel(p)>=128:
                        seen.add(p);stack.append(p)
            if len(points)>len(best):best=points
    mask=Image.new('L',im.size)
    for p in best:mask.putpixel(p,255)
    out=im.copy();out.putalpha(mask);return out

def rows(source,columns,frame_size,remove_detached=False):
    original=Image.open(source)
    clean=original.convert('RGBA') if original.mode=='RGBA' else matte(original)[0]
    result={}
    for row,name in enumerate(IDS):
        cells=[]
        for col in range(columns):
            cell=clean.crop((round(col*clean.width/columns),round(row*clean.height/6),round((col+1)*clean.width/columns),round((row+1)*clean.height/6)))
            if remove_detached:cell=largest_component(cell)
            cells.append(cell)
        # Common scale across an identity's complete action, never a separate fit per frame.
        boxes=[im.getbbox() for im in cells]
        w=max(b[2]-b[0] for b in boxes);h=max(b[3]-b[1] for b in boxes)
        scale=min((frame_size[0]-4)/w,(frame_size[1]-2)/h)
        atlas=Image.new('RGBA',(frame_size[0]*columns,frame_size[1]))
        for col,(cell,box) in enumerate(zip(cells,boxes)):
            cut=cell.crop(box);cut=cut.resize((round(cut.width*scale),round(cut.height*scale)),Image.Resampling.NEAREST)
            cut.putalpha(cut.getchannel('A').point(lambda x:255 if x>=128 else 0))
            atlas.alpha_composite(cut,(col*frame_size[0]+(frame_size[0]-cut.width)//2,frame_size[1]-1-cut.height))
        result[name]=atlas
    return result

def resource(task,folder,size,columns,animations,cover_name='background.png',detailed=False):
    fw,fh=size
    prefix=f'res://InheritanceTasks/Art/Pixel/v3/runtime/{folder}/'
    lines=['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="script"]',
        '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="appearance"]',
        f'[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/{task}_pixel.tscn" id="stage"]',
        f'[ext_resource type="Texture2D" path="{prefix}background.png" id="bg"]',
        f'[ext_resource type="Texture2D" path="{prefix}{cover_name}" id="cover"]']
    for name in IDS:lines.append(f'[ext_resource type="Texture2D" path="{prefix}{name}.png" id="{name}"]')
    portraits={name for name in IDS if (V3/'runtime'/folder/f'portrait-{name}.png').exists()}
    for name in portraits:lines.append(f'[ext_resource type="Texture2D" path="{prefix}portrait-{name}.png" id="portrait_{name}"]')
    for name in IDS:
        for i in range(columns):lines.extend([f'[sub_resource type="AtlasTexture" id="{name}_{i}"]',f'atlas = ExtResource("{name}")',f'region = Rect2({i*fw},0,{fw},{fh})','filter_clip = true'])
        actions=[]
        for item in animations:
            key,indices,loop,speed=item[:4]
            durations=item[4] if len(item)>4 else [1.0]*len(indices)
            entries=', '.join('{"duration": %s, "texture": SubResource("%s_%s")}'%(d,name,i) for i,d in zip(indices,durations))
            actions.append('{"frames": [%s], "name": &"%s", "loop": %s, "speed": %s}'%(entries,key,str(loop).lower(),speed))
        lines.extend([f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(actions)+']',f'[sub_resource type="Resource" id="avatar_{name}"]','script = ExtResource("appearance")',f'avatar_id = &"{name}_blogger"',f'costume_id = &"{task}"',f'portrait = SubResource("{name}_0")',f'atlas = ExtResource("{name}")',f'sprite_frames = SubResource("frames_{name}")',f'frame_size = Vector2i({fw},{fh})',f'anchors = {{&"feet": Vector2({fw/2},{fh-1})}}','reference_note = "原博主身份参考的直接生成衍生；装束与动作的艺术简化见来源记录。"'])
    avatars=', '.join(f'&"{n}_blogger": SubResource("avatar_{n}")' for n in IDS)
    lines.extend(['[resource]','script = ExtResource("script")','version = 3','stage_scene = ExtResource("stage")','background = ExtResource("bg")','cover = ExtResource("cover")',f'avatar_appearances = {{{avatars}}}',f'source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/{folder}-manifest.json"','properties = {"native_pixel_scale": 2, "status": "generated candidate; engine review tracked separately"}'])
    output='\n\n'.join(lines)+'\n'
    if detailed:
        output=output.replace('version = 3','version = 3\npixel_canvas_size = Vector2i(1000,600)').replace('"native_pixel_scale": 2','"native_pixel_scale": 1')
    for name in portraits:output=output.replace(f'portrait = SubResource("{name}_0")',f'portrait = ExtResource("portrait_{name}")')
    (V3/'resources'/f'{task}.tres').write_text(output,encoding='utf8')

def build():
    for task,folder,size,columns in [('huangmei_xi','huangmei',(256,256),6),('xingshan_min_ge','xingshan_min_ge',(168,240),2)]:
        srcfolder='huangmei' if folder=='huangmei' else 'xingshan'
        source=V3/'source'/srcfolder/'actors.png';dest=V3/'runtime'/folder;dest.mkdir(parents=True,exist_ok=True)
        actors=rows(source,columns,size,remove_detached=(columns==2))
        for name,im in actors.items():im.save(dest/f'{name}.png')
        if columns==6:
            background=Image.open(V3/'source/huangmei/background.png').convert('RGB').resize((1000,600),Image.Resampling.NEAREST)
            background.save(dest/'background.png')
            animations=[('ready',[0],False,1),('prepare',[1,2],False,3),('hold',[3],False,1),('release',[4],False,1),('recover',[4,5],False,3),('success',[4,5],False,3),('miss',[4],False,1)]
            cover=background.convert('RGBA');cover.alpha_composite(actors['travel'].crop((0,0,*size)).resize((320,320),Image.Resampling.NEAREST),(340,124));cover.save(dest/'cover.png')
            record={'source':str(source.relative_to(ROOT)), 'sha256':sha(source),'export':'256x256 shared action cells, preserved source colors, 1000x600 art viewport; no 16/20-color reduction','costume_reference':'user-provided 女驸马 video at 4s; black winged official hat, red robe and white water sleeves; roleplay simplification', 'capture':'No recording performed; scorer unchanged.'}
            (V3/'huangmei-manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')
        else:
            Image.open(dest/'background-0.png').save(dest/'background.png')
            animations=[('ready',[0],False,1),('wave',[1],False,1),('prepare',[0],False,1),('action',[1],False,1),('recover',[1],False,1)]
            cover=Image.open(dest/'background.png').convert('RGBA').resize((1000,600),Image.Resampling.NEAREST);cover.alpha_composite(actors['travel'].crop((0,0,*size)).resize((112,160),Image.Resampling.NEAREST),(45,370));cover.save(dest/'cover.png')
        resource(task,folder,size,columns,animations,'cover.png',detailed=True)

if __name__=='__main__':
    build()
    # The generated sheets are not an equal-row grid. Reapply the reviewed
    # explicit rectangles after a full rebuild, so hats cannot regress.
    from repair_avatar_crops_v4 import build as repair_reviewed_crops
    repair_reviewed_crops()
