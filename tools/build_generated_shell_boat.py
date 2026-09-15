from pathlib import Path
import json,hashlib
from PIL import Image,ImageDraw,ImageOps
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'InheritanceTasks/Art/Pixel/v3'
records=[]
for name,folder,size,colors in [('tv','ui',(576,348),24),('boat','shenzhou',(96,96),32)]:
    if name=='boat' and (BASE/'source/shenzhou/boat-rear-r2-green.png').exists():
        from build_shenzhou_camera_v3 import build
        build()
        records.append({'file':'InheritanceTasks/Art/Pixel/v3/runtime/shenzhou/boat.png','manifest':'shenzhou-camera-manifest.json','method':'Preserved generated rear camera correction; do not restore the rejected 96px/32-color export.'})
        continue
    source=BASE/'source'/folder/(name+'.png')
    im=Image.open(source).convert('RGBA')
    original_mode=Image.open(source).mode
    if name=='tv':
        im=im.resize(size,Image.Resampling.NEAREST)
        mask=Image.new('L',size,255)
        ImageDraw.Draw(mask).rectangle((12,24,511,323),fill=0)
        im=im.convert('RGB').quantize(colors=colors,dither=Image.Dither.NONE).convert('RGBA')
        im.putalpha(mask)
    else:
        # Generator delivered native alpha for this asset; retain it.
        bbox=im.getbbox()
        im=ImageOps.contain(im.crop(bbox),size,Image.Resampling.NEAREST)
        alpha=im.getchannel('A').point(lambda a:255 if a>=128 else 0)
        rgb=im.convert('RGB').quantize(colors=colors,dither=Image.Dither.NONE).convert('RGBA')
        rgb.putalpha(alpha)
        im=Image.new('RGBA',size)
        im.alpha_composite(rgb,((size[0]-rgb.width)//2,size[1]-rgb.height))
    target=BASE/'runtime'/folder/(name+'.png');im.save(target)
    records.append({'file':str(target.relative_to(ROOT)).replace('\\','/'),'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'original_mode':original_mode,'size':list(size),'colors':colors,'method':'built-in imagegen; shared-palette normalization, documented viewport mask or preserved native alpha'})
(BASE/'shell-boat-manifest.json').write_text(json.dumps({'assets':records,'boat_shape_reference':'https://hswhj.huangshi.gov.cn/xwzx/gzdt/202307/t20230711_1031116.html','status':'generated and normalized, awaiting actual scene review'},ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(records,ensure_ascii=False))
