"""Prepare fixed-density platform art, preserving gameplay world geometry."""
from pathlib import Path
import json
from PIL import Image
from collections import deque
from build_generated_pixel_v3 import matte,palette_rgba,sha
from build_generated_character_resources import resource

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
OLD=ROOT/'InheritanceTasks/Art/Pixel/v1/runtime/yandi_shennong_chuanshuo'
IDS=['travel','life','business','food','adventure','magic']
OUT=V3/'runtime/shennong'

def split(im,cols,rows,row=None):
    clean=im.convert('RGBA')
    real_alpha=im.mode=='RGBA' and clean.getchannel('A').getextrema()[0]<255
    cells=[]
    for y in (range(rows) if row is None else [row]):
        for x in range(cols):
            cell=clean.crop((round(x*clean.width/cols),round(y*clean.height/rows),round((x+1)*clean.width/cols),round((y+1)*clean.height/rows)))
            # Only border-connected technical green is background; outlined
            # herb leaves and the original clothing colors must survive.
            if not real_alpha:
                px=cell.load();queue=deque();seen=set()
                def green(p):
                    r,g,b,a=px[p];return g>110 and g>r+24 and g>b+24
                for cx in range(cell.width):queue.extend([(cx,0),(cx,cell.height-1)])
                for cy in range(cell.height):queue.extend([(0,cy),(cell.width-1,cy)])
                while queue:
                    p=queue.popleft()
                    if p in seen or not (0<=p[0]<cell.width and 0<=p[1]<cell.height):continue
                    seen.add(p)
                    if not green(p):continue
                    px[p]=(0,0,0,0)
                    queue.extend([(p[0]-1,p[1]),(p[0]+1,p[1]),(p[0],p[1]-1),(p[0],p[1]+1)])
            cells.append(cell)
    return cells

def normalize(cells):
    # One fixed crop/scale is shared by all poses. Centre does NOT follow each bounding box.
    boxes=[c.getbbox() for c in cells]
    left=min(b[0] for b in boxes);top=min(b[1] for b in boxes)
    right=max(b[2] for b in boxes);bottom=max(b[3] for b in boxes)
    # The user rejected the previous 20x24/16-color reduction. Keep the
    # generated master detail, then let the high-resolution stage display it.
    scale=min(288/(right-left),352/(bottom-top))
    w,h=round((right-left)*scale),round((bottom-top)*scale)
    frames=[]
    for c in cells:
        small=c.crop((left,top,right,bottom)).resize((w,h),Image.Resampling.NEAREST)
        small.putalpha(small.getchannel('A').point(lambda a:255 if a>=128 else 0))
        result=Image.new('RGBA',(320,384));result.alpha_composite(small,((320-w)//2,384-h));frames.append(result)
    return frames

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    records=[]
    poses=Image.open(V3/'source/shennong/poses.png')
    for row,name in enumerate(IDS):
        src=V3/'source/shennong'/f'{name}-run.png'
        if name=='food':src=V3/'source/shennong/food-run-user-reference.png'
        pose_cells=split(poses,6,6,row)
        frames=normalize(split(Image.open(src),4,2))+normalize(pose_cells)
        for i in [0,1,2,4,5,6,8,12,13]:
            box=frames[i].getbbox()
            if box and box[3]!=384:
                registered=Image.new('RGBA',(320,384));registered.alpha_composite(frames[i],(0,384-box[3]));frames[i]=registered
        atlas=Image.new('RGBA',(4480,384))
        for i,frame in enumerate(frames):atlas.alpha_composite(frame,(320*i,0))
        atlas.save(OUT/f'{name}.png')
        portrait=pose_cells[0].crop(pose_cells[0].getbbox())
        ratio=min(92/portrait.width,110/portrait.height)
        portrait=portrait.resize((round(portrait.width*ratio),round(portrait.height*ratio)),Image.Resampling.NEAREST)
        portrait_canvas=Image.new('RGBA',(96,112));portrait_canvas.alpha_composite(portrait,((96-portrait.width)//2,112-portrait.height))
        portrait_canvas.save(OUT/f'portrait-{name}.png')
        records.append({'avatar':name,'source_sha256':sha(src),'run_frames':8,'passing_frames':[2,6],'source_frame_size':[320,384],'independent_frame_scaling':False,'color_reduction':False})
    for i in range(3):
        im=Image.open(OLD/f'background-{i}.png').convert('RGB').resize((500,300),Image.Resampling.NEAREST)
        im.quantize(colors=48,dither=Image.Dither.NONE).convert('RGB').save(OUT/f'background-{i}.png')
    Image.open(OUT/'background-0.png').save(OUT/'background.png')
    tiles=Image.open(V3/'source/shennong/ground.png').convert('RGB')
    for col,name in enumerate(['forest','creek','ridge']):
        x=round(col*tiles.width/3);right=round((col+1)*tiles.width/3)
        # Standing edge is a flat crop of the grass cap; decorative tips never alter collisions.
        top=tiles.crop((x+4,76,right-4,tiles.height//2-4)).resize((64,64),Image.Resampling.NEAREST)
        fill=tiles.crop((x+4,tiles.height//2+4,right-4,tiles.height-4)).resize((64,56),Image.Resampling.NEAREST)
        top.paste(fill,(0,8));top.quantize(colors=24,dither=Image.Dither.NONE).convert('RGB').save(OUT/f'{name}.png')
    # Existing generated obstacle shapes are resized once to their actual collision footprints.
    for size in [(14,8),(14,11),(15,11),(14,10),(15,10)]:
        im=Image.open(OLD/'rock.png').convert('RGBA');im=im.crop(im.getbbox()).resize((size[0]*2,size[1]*2),Image.Resampling.NEAREST)
        palette_rgba(im,12).save(OUT/f'rock-{size[0]}x{size[1]}.png')
    for name,size in [('branch',(32,22)),('marker',(36,64))]:
        im=Image.open(OLD/f'{name}.png').convert('RGBA');im=im.crop(im.getbbox()).resize(size,Image.Resampling.NEAREST)
        palette_rgba(im,12).save(OUT/f'{name}.png')
    actions=[('ready',[8],False,1),('idle',[8],False,1),('prepare',[8],False,1),('run',list(range(8)),True,12,[.8,.85,1.2,.85,.8,.85,1.2,.85]),('jump_short',[9],False,1),('jump_long',[10],False,1),('fall',[11],False,1),('land',[12,8],False,10),('recover',[12,8],False,5),('gather',[13],False,1),('success',[13],False,1),('miss',[12],False,1)]
    resource('yandi_shennong_chuanshuo','shennong',(320,384),14,actions)
    res=V3/'resources/yandi_shennong_chuanshuo.tres';text=res.read_text(encoding='utf8').replace('version = 3','version = 3\npixel_canvas_size = Vector2i(1000,600)').replace('"native_pixel_scale": 2','"native_pixel_scale": 1, "detailed_platform": true, "camera_zoom": 2.0')
    res.write_text(text,encoding='utf8')
    (V3/'shennong-manifest.json').write_text(json.dumps({'version':3,'method':'User-approved generated master preserved in 320x384 cells; no palette reduction. 1000x600 art viewport and 2x world camera, with the same transform for ground/collisions/character.','records':records,'terrain':'Generated static caps and soil; source crops fixed to world coordinates','validation':'User rejected 20x24 reduction; replacement engine playback pending'},ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':
    build()
    # Pose rows have different boundaries in each column; the reviewed crop
    # pass preserves the run frames while removing neighboring-row fragments.
    from repair_avatar_crops_v4 import build as repair_reviewed_crops
    repair_reviewed_crops()
