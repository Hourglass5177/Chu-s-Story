"""Export generated music candidates without destructive downsampling/quantization.

Source artwork is never overwritten. Slicing and chroma matte conversion only.
"""
from pathlib import Path
import hashlib
import json
import re
from collections import deque
from PIL import Image, ImageFilter

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
IDS=['travel','life','business','food','adventure','magic']
TASKS={
 'laohekou_si_xian':('travel-pluck-r3.png',4,1,'partners.png',4,2,(384,188,232,360)),
 'tujia_saye_erhe':('travel-step-r2.png',4,2,'teacher-drummer.png',4,2,(404,296,192,256)),
 'jingzhou_hua_gu_xi':('travel-animation.png',4,1,'npcs.png',2,2,(582,190,245,380)),
 'han_ju':('travel-animation-r4.png',4,2,'npcs.png',4,2,(47,307,216,288)),
 'ti_qin_xi':('travel-animation-r5.png',4,2,'npcs.png',4,1,(335,105,365,487)),
 'gu_pen_ge':('travel-animation.png',4,1,'teacher.png',4,1,(597,170,245,380)),
}

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def matte(original):
 image=original.convert('RGBA')
 if original.mode=='RGBA' and image.getchannel('A').getextrema()[0]<255:return image
 # Green technical backdrop only. Preserve the source colours of opaque pixels.
 pixels=[]
 for r,g,b,a in image.getdata():
  pixels.append((0,0,0,0) if g>100 and g>max(r,b)+45 else (r,g,b,a))
 image.putdata(pixels)
 # Remove green contamination only at an existing matte edge, not every teal fabric.
 edge=image.getchannel('A').filter(ImageFilter.MinFilter(3))
 data=[]
 for (r,g,b,a),interior in zip(image.getdata(),edge.getdata()):
  if a and interior==0 and g>max(r,b)+10:g=max(r,b)
  data.append((r,g,b,a))
 image.putdata(data)
 return image

def slice_strip(path,columns,rows,clear_grid_border=False):
 original=Image.open(path)
 clean=matte(original)
 size=(clean.width//columns,clean.height//rows)
 atlas=Image.new('RGBA',(size[0]*columns*rows,size[1]))
 for i in range(columns*rows):
  x=round((i%columns)*clean.width/columns);y=round((i//columns)*clean.height/rows)
  frame=clean.crop((x,y,x+size[0],y+size[1]))
  if clear_grid_border:
   # Some NPC source grids put a thin separator on the cell boundary.
   # All approved silhouettes have padding; remove only the technical border.
   frame.paste((0,0,0,0),(0,0,size[0],3))
   frame.paste((0,0,0,0),(0,size[1]-3,size[0],size[1]))
  atlas.alpha_composite(frame,(i*size[0],0))
 return atlas,size,original.mode=='RGBA' and original.getchannel('A').getextrema()[0]<255

def clear_small_islands(atlas,size,limit=200):
 # Whole-strip generation can leave the adjacent frame's bow tip in an empty
 # margin. Only remove disconnected tiny alpha components; no palette changes.
 width,height=size
 pixels=atlas.load()
 for frame in range(atlas.width//width):
  left=frame*width;seen=set()
  for y in range(height):
   for x in range(width):
    if (x,y) in seen or not pixels[left+x,y][3]:continue
    seen.add((x,y));queue=deque([(x,y)]);component=[]
    while queue:
     cx,cy=queue.popleft();component.append((cx,cy))
     for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
      nx,ny=cx+dx,cy+dy
      if 0<=nx<width and 0<=ny<height and (nx,ny) not in seen and pixels[left+nx,ny][3]:
       seen.add((nx,ny));queue.append((nx,ny))
    if len(component)<limit:
     for cx,cy in component:pixels[left+cx,cy]=(0,0,0,0)
 return atlas

def compose_cover(task,background,actor,actor_size,npcs,npc_size,actor_rect):
 # The preparation cover contains the same participants and instruments as the
 # playable stage. An empty theatre does not explain the spotlight activity.
 cover=background.resize((1000,600),Image.Resampling.LANCZOS)
 placements={
  'laohekou_si_xian':[(0,(90,278,260,202)),(4,(658,278,260,202))],
  'tujia_saye_erhe':[(0,(404,110,192,256)),(0,(224,192,192,256)),(0,(612,192,192,256)),(4,(794,146,192,256))],
  'jingzhou_hua_gu_xi':[(1,(120,10,270,270))],
  'han_ju':[(6,(210,60,180,270))],
  'ti_qin_xi':[(1,(225-round(npc_size[0]*90/npc_size[1]),48,round(npc_size[0]*180/npc_size[1]),180))],
  'gu_pen_ge':[(1,(162,170,245,380))],
 }
 w,h=npc_size
 for frame,rect in placements[task]:
  layer=npcs.crop((frame*w,0,(frame+1)*w,h)).resize(rect[2:],Image.Resampling.LANCZOS)
  cover.alpha_composite(layer,rect[:2])
 layer=actor.crop((0,0,*actor_size)).resize(actor_rect[2:],Image.Resampling.LANCZOS)
 cover.alpha_composite(layer,actor_rect[:2])
 return cover

def actions(task):
 # Shared labels are compatibility fallbacks; each stage selects its own semantics.
 result={k:([v],False,1) for k,v in {'ready':0,'prepare':1,'hold':2,'release':3,'miss':3,'recover':0,'success':0,'rest':0}.items()}
 if task=='laohekou_si_xian':
  result.update({'pluck':([2,3,0],False,10),'pluck_recover':([3,0],False,10),'miss':([2,3,0],False,10),'recover':([3,0],False,8)})
 elif task=='tujia_saye_erhe':
  result.update({'prepare_left':([1],False,1),'prepare_right':([5],False,1),'step_left':([2,3,0],False,8),'step_right':([6,7,4],False,8),'step_recover':([0],False,1)})
 elif task=='jingzhou_hua_gu_xi':
  result.update({'voice_short':([2,3,0],False,8),'voice_sustain':([2],False,1),'voice_close':([3,0],False,7),'recover':([3,0],False,7)})
 elif task=='han_ju':
  result.update({'spotlight_left':([5,6,7],False,12),'spotlight_right':([1,2,3],False,12),'prepare_left':([5],False,1),'prepare_right':([1],False,1)})
 elif task=='ti_qin_xi':
  result.update({'prepare_left':([0],False,1),'prepare_right':([4],False,1),'bow_short_left':([1,2,3,4],False,16),'bow_short_right':([3,2,1,0],False,16),'bow_long_left':([0,1,2,3,4],False,3),'bow_long_right':([4,3,2,1,0],False,3),'bow_close_left':([4,7],False,8),'bow_close_right':([0],False,1)})
 elif task=='gu_pen_ge':
  result.update({'hold':([2,3,0],False,10),'drum_hit':([2,3,0],False,10),'recover':([3,0],False,8)})
 return result

def write_resource(task,records):
 lines=['[gd_resource type="Resource" script_class="HeritageTaskPresentation" format=3]','',
 '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_task_presentation.gd" id="1"]',
 '[ext_resource type="Script" path="res://InheritanceTasks/Data/heritage_avatar_appearance.gd" id="2"]',
 f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{task}/background.png" id="bg"]',
 f'[ext_resource type="PackedScene" path="res://InheritanceTasks/Presentation/Stages/{task}_pixel.tscn" id="stage"]']
 for record in records:
  name=record['actor']
  lines.extend([f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{task}/{name}.png" id="atlas_{name}"]',f'[ext_resource type="Texture2D" path="res://InheritanceTasks/Art/Pixel/v3/runtime/{task}/cover-{name}.png" id="cover_{name}"]'])
 for record in records:
  name=record['actor'];w,h=record['frame_size'];count=record['frames']
  for i in range(count):
   lines.extend([f'[sub_resource type="AtlasTexture" id="{name}_{i}"]',f'atlas = ExtResource("atlas_{name}")',f'region = Rect2({i*w}, 0, {w}, {h})','filter_clip = true'])
  entries=[]
  for action,(indices,loop,speed) in actions(task).items():
   frames=', '.join('{"duration": 1.0, "texture": SubResource("%s_%d")}'%(name,i) for i in indices)
   entries.append('{"frames": [%s], "loop": %s, "name": &"%s", "speed": %s}'%(frames,str(loop).lower(),action,speed))
  lines.extend([f'[sub_resource type="SpriteFrames" id="frames_{name}"]','animations = ['+',\n'.join(entries)+']',f'[sub_resource type="Resource" id="avatar_{name}"]','script = ExtResource("2")',f'avatar_id = &"{name}_blogger"',f'costume_id = &"{task}"',f'portrait = SubResource("{name}_0")',f'sprite_frames = SubResource("frames_{name}")',f'atlas = ExtResource("atlas_{name}")',f'frame_size = Vector2i({w}, {h})','reference_note = "原博主身份生成衍生；保留原帧尺寸和原色。游戏动作候选，尚未获用户美术验收。"'])
 appearances=', '.join('&"%s_blogger": SubResource("avatar_%s")'%(r['actor'],r['actor']) for r in records)
 covers=', '.join('&"%s_blogger": ExtResource("cover_%s")'%(r['actor'],r['actor']) for r in records)
 lines.extend(['[resource]','script = ExtResource("1")','version = 3','pixel_canvas_size = Vector2i(1000, 600)','logical_stage_size = Vector2i(1000, 600)','background = ExtResource("bg")','cover = ExtResource("cover_travel")',f'avatar_covers = {{{covers}}}',f'avatar_appearances = {{{appearances}}}',f'properties = {{"generated_music": true, "source_resolution_preserved": true, "art_status": "生成动作候选；未获用户验收", "chart_review": "游戏编排待听审"}}',f'source_manifest_path = "res://InheritanceTasks/Art/Pixel/v3/{task}-manifest.json"','stage_scene = ExtResource("stage")'])
 (V3/'resources'/f'{task}.tres').write_text('\n\n'.join(lines)+'\n',encoding='utf-8')

def build(task,spec):
 first,cols,rows,npc,ncols,nrows,rect=spec
 source=V3/'source'/task;out=V3/'runtime'/task;out.mkdir(parents=True,exist_ok=True)
 if task in ['jingzhou_hua_gu_xi','han_ju','ti_qin_xi'] and (source/'npcs-r4-green.png').exists():npc='npcs-r4-green.png'
 bg=Image.open(source/'background.png').convert('RGBA');bg.save(out/'background.png')
 npc_atlas,npc_size,npc_alpha=slice_strip(source/npc,ncols,nrows,True);npc_atlas.save(out/'npcs.png')
 records=[]
 cover_records=[]
 for name in IDS:
  path=source/(first if name=='travel' else name+'-animation.png')
  for override in ([source/'food-animation-r2.png'] if task=='tujia_saye_erhe' and name=='food' else [source/'adventure-animation-r2.png'] if task=='ti_qin_xi' and name=='adventure' else []):
   if override.exists():path=override
  if not path.exists():raise FileNotFoundError(path)
  atlas,size,native_alpha=slice_strip(path,cols,rows)
  if task=='ti_qin_xi':atlas=clear_small_islands(atlas,size)
  target=out/(name+'.png');atlas.save(target)
  records.append({'actor':name,'source':path.relative_to(ROOT).as_posix(),'source_sha256':digest(path),'source_size':Image.open(path).size,'native_alpha':native_alpha,'frame_size':size,'frames':cols*rows,'runtime':target.relative_to(ROOT).as_posix(),'runtime_sha256':digest(target),'normal_playback_reviewed':False})
  cover=compose_cover(task,bg,atlas,size,npc_atlas,npc_size,rect);cover.save(out/('cover-'+name+'.png'))
  cover_path=out/('cover-'+name+'.png')
  cover_records.append({'actor':name,'runtime':cover_path.relative_to(ROOT).as_posix(),'sha256':digest(cover_path)})
 write_resource(task,records)
 manifest={'method':'imagegen whole strips; native cell slicing, technical green matte where needed; no palette quantization or source pixel reduction','task':task,'status':'generated candidates; not user accepted','pixel_canvas':[1000,600],'logical_stage':[1000,600],'actors':records,'npc':{'source':str((source/npc).relative_to(ROOT)),'frame_size':npc_size,'frames':ncols*nrows,'native_alpha':npc_alpha,'source_sha256':digest(source/npc)},'culture':'New game practice performance. Costume/instrument references documented in prompts; exact motions are artistic/gameplay interpretations. Gupen drum form and authentic audio remain awaiting source video.','pending':['normal-speed full-scene review','black/white edge review','user experience review','human listening review of audio phrase cuts']}
 manifest['covers']={'method':'Composition from the same generated stage layers, including supporting performers. Not a gameplay screenshot.','items':cover_records}
 (V3/(task+'-manifest.json')).write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
 definition=ROOT/'InheritanceTasks/Definitions'/f'{task}.tres';text=definition.read_text(encoding='utf-8');text=re.sub(r'v[123]/resources/'+task+r'\.tres','v3/resources/'+task+'.tres',text);definition.write_text(text,encoding='utf-8')
 print(task,[(r['actor'],r['frame_size']) for r in records])

if __name__=='__main__':
 import sys
 for task,spec in TASKS.items():
  if len(sys.argv)==1 or task in sys.argv[1:]:build(task,spec)
