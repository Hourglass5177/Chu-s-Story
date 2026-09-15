"""Keep the revised generated boat detail; remove only border-connected matte."""
from pathlib import Path
import json
from PIL import Image,ImageOps
from build_generated_shennong_v3 import split
from build_generated_pixel_v3 import sha

ROOT=Path(__file__).resolve().parents[1]
V3=ROOT/'InheritanceTasks/Art/Pixel/v3'

def build():
    source=V3/'source/shenzhou/boat-rear-r2-green.png'
    clean=split(Image.open(source),1,1)[0]
    clean=clean.crop(clean.getbbox())
    clean=ImageOps.contain(clean,(384,512),Image.Resampling.NEAREST)
    clean.putalpha(clean.getchannel('A').point(lambda a:255 if a>=128 else 0))
    output=Image.new('RGBA',(384,512));output.alpha_composite(clean,((384-clean.width)//2,512-clean.height))
    target=V3/'runtime/shenzhou/boat.png';output.save(target)
    record={'source':str(source.relative_to(ROOT)),'source_sha256':sha(source),'output_sha256':sha(target),
        'frame_size':[384,512],'method':'Generated high rear view; border-connected green technical matte removed; source colors preserved, no palette reduction.',
        'cultural_reference':'https://hswhj.huangshi.gov.cn/xwzx/gzdt/202307/t20230711_1031116.html',
        'status':'Generated camera correction, actual scene and user review recorded separately; artistic simplification, not a measured reconstruction.'}
    (V3/'shenzhou-camera-manifest.json').write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':build()
