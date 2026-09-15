"""Technical re-extraction only: explicit source rectangles, no artwork repaint.

Keep approved run frames unchanged. Remove only border-connected green matte;
all outlined herbs, hats and costume colors inside each rectangle survive.
"""
from pathlib import Path
import json, shutil
import numpy as np
from PIL import Image, ImageDraw
from build_generated_character_resources import largest_component

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
IDS=['travel','life','business','food','adventure','magic']
OUT=ROOT/'artifacts/input-revision/crops'

def clean(im,rect):
    cell=im.crop(rect).convert('RGBA'); a=np.array(cell)
    r,g,b=[a[:,:,i].astype(int) for i in range(3)]
    green=(g>110)&(g>r+24)&(g>b+24)
    mask=Image.new('L',(cell.width+2,cell.height+2),255)
    mask.paste(Image.fromarray((green*255).astype('uint8')),(1,1))
    ImageDraw.floodfill(mask,(0,0),128)
    remove=np.array(mask)[1:-1,1:-1]==128;a[remove]=0
    # Each rectangle contains one connected full character (including held
    # objects). Detached reference birds and neighboring-row shoe fragments
    # have been checked against the whole source sheet and are excluded.
    return largest_component(Image.fromarray(a))

def registered(cells,size):
    boxes=[c.getbbox() for c in cells]
    ratio=min((size[0]-24)/max(b[2]-b[0] for b in boxes),(size[1]-16)/max(b[3]-b[1] for b in boxes))
    result=[]
    for c,b in zip(cells,boxes):
        c=c.crop(b);c=c.resize((round(c.width*ratio),round(c.height*ratio)),Image.Resampling.NEAREST)
        frame=Image.new('RGBA',size);frame.alpha_composite(c,((size[0]-c.width)//2,size[1]-4-c.height));result.append(frame)
    return result

def archive(path):
    dest=V3/'source/crop-repair-v4/previous'/path.relative_to(V3/'runtime')
    dest.parent.mkdir(parents=True,exist_ok=True)
    if not dest.exists():shutil.copy2(path,dest)

def build():
    OUT.mkdir(parents=True,exist_ok=True)
    records=[]
    source=Image.open(V3/'source/xingshan/actors.png')
    y=[0,246,489,716,947,1181,1470]
    # Explicit nonuniform rows; crop left of bodies excludes detached birds.
    for row,name in enumerate(IDS):
        rects=[(345,y[row],530,y[row+1]),(601,y[row],780,y[row+1])]
        # Travel's waving hand is left of the other right-column silhouettes.
        cells=[clean(source,r) for r in rects]
        frames=registered(cells,(168,240));atlas=Image.new('RGBA',(336,240))
        for i,c in enumerate(frames):atlas.alpha_composite(c,(i*168,0))
        path=V3/'runtime/xingshan_min_ge'/f'{name}.png';archive(path);atlas.save(path)
        records.append({'task':'xingshan','avatar':name,'rectangles':rects,'size':[168,240]})
    source=Image.open(V3/'source/shennong/poses.png')
    xs=[0,230,466,704,938,1175,1402]
    ys=[[0,203,394,579,754,939,1122],[0,202,394,578,754,936,1122],
        [0,199,392,573,748,933,1122],[0,201,395,578,758,940,1122],
        [0,201,414,586,775,948,1122],[0,207,414,586,774,947,1122]]
    for row,name in enumerate(IDS):
        rects=[(xs[col],ys[col][row],xs[col+1],ys[col][row+1]) for col in range(6)]
        cells=[clean(source,r) for r in rects];frames=registered(cells,(320,384))
        path=V3/'runtime/shennong'/f'{name}.png';archive(path)
        atlas=Image.open(path).convert('RGBA')
        atlas.paste((0,0,0,0),(2560,0,4480,384))
        for i,c in enumerate(frames):atlas.alpha_composite(c,((i+8)*320,0))
        atlas.save(path)
        preview=Image.new('RGBA',(1920,384),(42,43,49,255))
        for i,c in enumerate(frames):preview.alpha_composite(c,(i*320,0))
        preview.save(OUT/f'shennong-{name}.png')
        records.append({'task':'shennong','avatar':name,'rectangles':rects,'size':[320,384],'run_frames_unchanged':True})
    contact=Image.new('RGBA',(672,720),(42,43,49,255))
    for i,name in enumerate(IDS):contact.alpha_composite(Image.open(V3/'runtime/xingshan_min_ge'/f'{name}.png'),((i%2)*336,(i//2)*240))
    contact.save(OUT/'xingshan-six.png')
    (V3/'source/crop-repair-v4/manifest.json').write_text(json.dumps({'version':4,'records':records,'review':'explicit rectangles; exported whole-body review pending'},ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':build()
