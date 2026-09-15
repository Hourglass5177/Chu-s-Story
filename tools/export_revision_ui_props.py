"""Technical matte export of generated UI/prop candidates, originals retained."""
from pathlib import Path
import json,shutil
import numpy as np
from PIL import Image
from build_generated_pixel_v3 import matte,sha
ROOT=Path(__file__).resolve().parents[1];V3=ROOT/'InheritanceTasks/Art/Pixel/v3'
GEN=Path('F:/Tools/OpenAI/CodexHome/generated_images/01a08252-f1c9-7c52-ab42-f49111f72612')

def main():
    source=V3/'source/ui-v4';source.mkdir(exist_ok=True)
    original=GEN/'exec-6a6125e5-491a-44d1-818e-0f8ccf76d809.png'
    shutil.copy2(original,source/'chuwu-tv-v2.png')
    im=Image.open(original).convert('RGBA');a=np.array(im);r,g,b=[a[:,:,i].astype(int) for i in range(3)]
    # The tool returned an RGB gray checkerboard, not native transparency.
    # All lettering/outline is warm-colored; neutral checker pixels are matte.
    a[:,:,3]=np.where((r>=g)&(g-b>8),255,0)
    im=Image.fromarray(a);im=im.crop(im.getbbox());im.save(V3/'runtime/ui/chuwu-tv-v1.png')
    original=GEN/'exec-dadc30b6-e1a5-4009-9f31-2aac712536c7.png'
    shutil.copy2(original,source/'river-boat-v2.png')
    im=matte(Image.open(original))[0]
    a=np.array(im);a[:,:,3]=np.where(a[:,:,3]>=128,255,0)
    im=Image.fromarray(a);im=im.crop(im.getbbox())
    im.save(V3/'runtime/shenzhou/obstacle-boat-v4.png')
    (source/'export-manifest.json').write_text(json.dumps({'version':4,'tool':'built-in imagegen','assets':[
      {'name':'楚物TV','source':'chuwu-tv-v2.png','matte':'Generated RGB checkerboard removed using neutral/warm separation; no lettering recolored','prompt':'Preserve 楚物TV letter shapes; remove brown glow and plate; cream/gold pixel wordmark with close dark outline'},
      {'name':'ordinary river boat','source':'river-boat-v2.png','matte':'native alpha preserved, green residue removed','prompt':'Broad short wooden cargo lighter, rear above 35 degrees, strong foreshortening, no people or ceremonial decoration'}],
      'review':'source and exports inspected; engine scale review pending'},ensure_ascii=False,indent=2),encoding='utf8')

if __name__=='__main__':main()
