"""Export generated motion art. Originals and exact generation prompts stay in source/."""
from pathlib import Path
import json
from PIL import Image
from build_generated_pixel_v3 import palette_rgba, matte, sha

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
OLD=ROOT/'InheritanceTasks/Art/Pixel/v1/runtime'
IDS=['travel','life','business','food','adventure','magic']

def grid(source, cols, rows, width, height, colors=20):
    original=Image.open(source)
    clean=original.convert('RGBA') if original.mode=='RGBA' else matte(original)[0]
    # Preserve source cell scale/spacing for the entire sequence, never fit each pose.
    atlas=Image.new('RGBA',(cols*width,rows*height))
    for row in range(rows):
        for col in range(cols):
            box=(round(col*clean.width/cols),round(row*clean.height/rows),round((col+1)*clean.width/cols),round((row+1)*clean.height/rows))
            cell=clean.crop(box).resize((width,height),Image.Resampling.NEAREST)
            cell.putalpha(cell.getchannel('A').point(lambda a:255 if a>=128 else 0))
            atlas.alpha_composite(cell,(col*width,row*height))
    return palette_rgba(atlas,colors) if colors else atlas

def build_birds():
    dest=V3/'runtime/xingshan_min_ge';dest.mkdir(parents=True,exist_ok=True)
    source=V3/'source/xingshan/bird.png'
    grid(source,4,3,128,128,0).save(dest/'bird.png')
    grid(source,4,3,128,128,0).save(dest/'followers.png')
    for i in range(4):
        Image.open(OLD/'xingshan_min_ge'/f'background-{i}.png').convert('RGB').resize((500,300),Image.Resampling.NEAREST).quantize(colors=48,dither=Image.Dither.NONE).convert('RGB').save(dest/f'background-{i}.png')
    for name,width in [('gate-top',65),('gate-bottom',70)]:
        im=Image.open(OLD/'xingshan_min_ge'/f'{name}.png')
        palette_rgba(im.resize((width,im.height//2),Image.Resampling.NEAREST),24).save(dest/f'{name}.png')
    record={'version':3,'source':str(source.relative_to(ROOT)),'sha256':sha(source),'frame_layout':[4,3],'native_main':[128,128],'native_followers':[128,128], 'export':'Source colors preserved; main and followers display at their original gameplay sizes in a 1000x600 art viewport.',
            'actions':{'flap':[0,1,2,3,4,5],'glide':[6],'descend':[7],'miss':[8],'recover':[9],'land':[10,11]},
            'rules':'No change to flight, gate route, song clock, collisions or scoring. Followers use existing independent history.'}
    (V3/'xingshan_min_ge-manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':
    build_birds()
