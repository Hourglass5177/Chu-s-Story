"""Read-only montage of original identities for the generator's 5-reference limit."""
from pathlib import Path
from PIL import Image, ImageOps
ROOT=Path(__file__).resolve().parents[1]
names=['旅行博主','生活博主','商业博主','美食博主','探险博主','魔术博主']
board=Image.new('RGB',(1500,1200),'#eee2cc')
for i,name in enumerate(names):
    source=ROOT/'arts/素材合集/sprite及立绘/Sprite/角色'/f'{name}.png'
    im=Image.open(source).convert('RGBA')
    bbox=im.getbbox()
    im=ImageOps.contain(im.crop(bbox),(470,570),Image.Resampling.LANCZOS)
    board.paste(im,(i%3*500+(500-im.width)//2,i//3*600+(600-im.height)//2),im)
out=ROOT/'InheritanceTasks/Art/Pixel/v3/references/avatar-originals.png'
out.parent.mkdir(parents=True,exist_ok=True);board.save(out)
print(out)
