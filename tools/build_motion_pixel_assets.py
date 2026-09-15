"""Slice generated motion-stage art. Sources stay intact; no creative drawing."""
from pathlib import Path
import hashlib
import json
import numpy as np
import cv2
from PIL import Image
from build_pixel_assets import alpha_image, normalized_strip, save_atlas

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v1'
SRC = ART / 'source'
OUT = ART / 'runtime'
records = []

def boxes(image, cols, rows):
    return [[round(x*image.width/cols),round(y*image.height/rows),round((x+1)*image.width/cols),round((y+1)*image.height/rows)] for y in range(rows) for x in range(cols)]

def save(image, relative, source, anchor=None):
    target=OUT/relative
    target.parent.mkdir(parents=True,exist_ok=True)
    image.save(target)
    records.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'source':source,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'size':list(image.size),'anchor':anchor,'status':'normalized_pending_engine_review'})

def background(name, cols, rows):
    source=f'{name}-background'+('-atlas' if cols*rows>1 else '')+'.png'
    im=Image.open(SRC/source).convert('RGBA')
    for i,box in enumerate(boxes(im,cols,rows)):
        save(im.crop(box).resize((500,300),Image.Resampling.NEAREST),f'{name}/background-{i}.png',source)

def sprites(source, cols, rows, size, target):
    im=alpha_image(SRC/source,'green')
    # Generated rows have small baseline drift. Segment whole silhouettes before
    # ordering by grid, so a nominal cut never clips feet or imports another row.
    data=np.array(im)
    count,labels,stats,centers=cv2.connectedComponentsWithStats((data[:,:,3]>100).astype('uint8'))
    components={}
    for idx in range(1,count):
        x,y,w,h,area=stats[idx]
        if area<1000:continue
        cx,cy=centers[idx]
        cell=(min(rows-1,int(cy/im.height*rows)),min(cols-1,int(cx/im.width*cols)))
        if cell not in components or area>stats[components[cell],4]:components[cell]=idx
    if len(components)!=cols*rows:raise ValueError(f'{source}: expected {cols*rows} silhouettes, found {len(components)}')
    cells=[]
    for row in range(rows):
        for col in range(cols):
            idx=components[(row,col)];x,y,w,h,_=stats[idx]
            cut=data[y:y+h,x:x+w].copy()
            cut[labels[y:y+h,x:x+w]!=idx]=0
            cells.append(Image.fromarray(cut))
    scale=min((size[0]-4)/max(c.width for c in cells),(size[1]-4)/max(c.height for c in cells))
    frames=[]
    for cell in cells:
        cell=cell.resize((max(1,round(cell.width*scale)),max(1,round(cell.height*scale))),Image.Resampling.NEAREST)
        frame=Image.new('RGBA',size)
        frame.alpha_composite(cell,((size[0]-cell.width)//2,size[1]-2-cell.height))
        frames.append(frame)
    save_atlas(frames,OUT/target,cols)
    records.append({'file':str((OUT/target).relative_to(ROOT)).replace('\\','/'),'source':source,'size':list(size),'columns':cols,'rows':rows,'anchor':[size[0]/2,size[1]-2],'status':'normalized_pending_engine_review'})
    return frames

def prop(im,box,size,relative,source):
    cut=im.crop(box)
    cut=cut.crop(cut.getbbox())
    save(cut.resize(size,Image.Resampling.NEAREST),relative,source)

def main():
    for name,c,r in [('yandi_shennong_chuanshuo',1,3),('dong_yong_chuanshuo',1,1),('xingshan_min_ge',2,2),('xisai_shenzhou_hui',1,1)]: background(name,c,r)
    sprites('yandi_shennong_chuanshuo-avatars-v2.png',10,6,(48,64),'yandi_shennong_chuanshuo/avatars.png')
    cart_frames=sprites('dong_yong_chuanshuo-avatars.png',8,6,(128,160),'dong_yong_chuanshuo/avatars.png')
    # Derive the visible right-hand contact point from skin pixels near torso,
    # retaining per-pose positions rather than assuming every generated pose aligns.
    hands=[]
    for frame in cart_frames:
        px=np.array(frame); yy,xx=np.indices(px.shape[:2]); r,g,b=[px[:,:,i].astype(int) for i in range(3)]
        skin=(px[:,:,3]>180)&(r>175)&(g>105)&(b>60)&(r>g+10)&(g>b+8)&(yy>45)&(yy<124)&(xx>60)
        ys,xs=np.where(skin)
        if len(xs):
            end=xs.max(); select=xs>=end-3; hands.append([float(xs[select].mean()),float(ys[select].mean())])
        else: hands.append([106.,95.])
    (OUT/'dong_yong_chuanshuo/hand-anchors.json').write_text(json.dumps(hands),encoding='utf-8')
    outdoor=sprites('river-field-avatars.png',4,6,(112,160),'outdoor-avatars.png')
    for name,start in [('xingshan_min_ge',0),('xisai_shenzhou_hui',2)]:
        frames=[outdoor[row*4+start+col] for row in range(6) for col in range(2)]
        save_atlas(frames,OUT/name/'avatars.png',2)
    source='xingshan_min_ge-bird-atlas.png';im=alpha_image(SRC/source)
    # Common cell transform preserves bird body location across wing changes.
    bird_frames=[]
    for box in boxes(im,4,2):
        cut=im.crop(box).resize((64,64),Image.Resampling.NEAREST)
        data=np.array(cut);data[data[:,:,3]<128]=0
        bird_frames.append(Image.fromarray(data))
    save_atlas(bird_frames,OUT/'xingshan_min_ge/bird.png',4)
    source='xisai_shenzhou_hui-boat.png';im=alpha_image(SRC/source,'green')
    prop(im,(0,0,im.width,im.height),(128,176),'xisai_shenzhou_hui/boat.png',source)
    source='dong_yong_chuanshuo-cart-props.png';im=alpha_image(SRC/source,'green')
    for name,box,sz in [('cart',[0,0,.60,.42],(240,84)),('wheel',[.64,0,1,.44],(64,64)),('father',[.18,.42,.5,1],(80,112)),('bundle',[.62,.56,.92,.98],(48,40))]:
        prop(im,[round(box[0]*im.width),round(box[1]*im.height),round(box[2]*im.width),round(box[3]*im.height)],sz,f'dong_yong_chuanshuo/{name}.png',source)
    source='yandi_shennong_chuanshuo-terrain.png';im=alpha_image(SRC/source,'green')
    for name,box,sz in zip(['forest','creek','ridge','rock','branch','marker'],boxes(im,3,2),[(96,64)]*3+[(32,20),(112,24),(40,64)]):
        prop(im,box,sz,f'yandi_shennong_chuanshuo/{name}.png',source)
    source='xingshan_min_ge-gates.png';im=alpha_image(SRC/source)
    data=np.array(im);data[data[:,:,3]<160]=0;im=Image.fromarray(data)
    for name,box in zip(['gate-bottom','gate-top'],boxes(im,2,1)):
        prop(im,box,(96,192),f'xingshan_min_ge/{name}.png',source)
    known={r['file']:r for r in records}
    for folder in ['yandi_shennong_chuanshuo','dong_yong_chuanshuo','xingshan_min_ge','xisai_shenzhou_hui']:
        for path in sorted((OUT/folder).glob('*')):
            if path.suffix not in ['.png','.json']:continue
            key=str(path.relative_to(ROOT)).replace('\\','/')
            if key not in known:
                record={'file':key,'source':'motion-art-generation-log.json','status':'normalized_pending_engine_review'}
                records.append(record)
            else:record=known[key]
            record['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
            if path.suffix=='.png':record['texture_size']=list(Image.open(path).size)
    (ART/'motion-runtime-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Normalized motion assets: {len(records)} recorded files plus avatar/bird atlases, source originals preserved.')

if __name__=='__main__':main()
