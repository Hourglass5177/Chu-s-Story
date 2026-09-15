"""Compose review boards and inventory existing rendered art, without generating art."""
from pathlib import Path
import hashlib
import json
import re
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v1'
REVIEW = ROOT / 'artifacts/pixel-art-review'
NAMES = ['旅行博主', '生活博主', '商业博主', '美食博主', '探险博主', '魔术博主']
IDS = ['travel', 'life', 'business', 'food', 'adventure', 'magic']
FONT = 'C:/Windows/Fonts/msyh.ttc'


def local(path): return ROOT / path.removeprefix('res://')
def font(size): return ImageFont.truetype(FONT, size)
def paste(board, picture, box, nearest=False):
    image = ImageOps.contain(picture.convert('RGBA'), (box[2], box[3]), Image.Resampling.NEAREST if nearest else Image.Resampling.LANCZOS)
    board.paste(image, (box[0] + (box[2]-image.width)//2, box[1] + (box[3]-image.height)//2), image)


def build():
    entries = json.loads((ART/'presentation-manifest.json').read_text(encoding='utf-8'))
    boards = ART / 'boards'
    covers = ART / 'runtime/covers'
    boards.mkdir(exist_ok=True); covers.mkdir(exist_ok=True)
    for entry in entries:
        ident = entry['task_id']
        text = (ROOT/'InheritanceTasks/Definitions'/f'{ident}.tres').read_text(encoding='utf-8')
        title = re.search(r'^heritage_name = "(.*)"', text, re.M)[1]
        main = REVIEW/f'{ident}-travel-scene.png'
        result = REVIEW/f'{ident}-travel-result.png'
        if not main.exists() or not result.exists(): raise FileNotFoundError(f'{ident}: missing engine review')
        pixel = REVIEW/f'{ident}-travel-pixel.png'
        # A reviewed cover may use a clearer crop of an actual gameplay frame.
        # Keep those explicit sources instead of replacing them with an arbitrary
        # opening-state capture on every delivery-board rebuild.
        checked_cover = ART / 'runtime/cover-source' / f'{ident}.png'
        if checked_cover.exists(): cover = Image.open(checked_cover).convert('RGBA')
        elif pixel.exists(): cover = Image.open(pixel).convert('RGBA')
        else:
            cover = Image.open(local(entry['background'])).convert('RGBA')
            if entry.get('story_thumbnails'):
                for i, path in enumerate(entry['story_thumbnails']): paste(cover, Image.open(local(path)), (8+i*123,80,116,150), True)
        cover.resize((500,300),Image.Resampling.NEAREST).save(covers/f'{ident}.png')
        entry['cover'] = f'res://InheritanceTasks/Art/Pixel/v1/runtime/covers/{ident}.png'
        board = Image.new('RGB',(1800,1430),'#f3e7d1')
        draw = ImageDraw.Draw(board)
        draw.text((35,20),f'{title}  像素制作检查板',fill='#382a24',font=font(40))
        draw.text((36,74),'当前引擎合成 · 视觉状态采样 · 不作为普通输入通关证据',fill='#705d4e',font=font(22))
        paste(board,Image.open(main),(30,120,1080,650))
        draw.text((1140,125),'预备与关键动作',fill='#382a24',font=font(27))
        atlas = Image.open(local(entry['atlas'])).convert('RGBA')
        w,h=entry.get('frame_size',[128,128]); cols=entry.get('columns',6)
        for i, c in enumerate([0,1,min(2,cols-1),min(3,cols-1)]):
            frame = atlas.crop((c*w,0,(c+1)*w,h))
            paste(board,frame,(1140+(i%2)*300,180+(i//2)*250,260,225),True)
        draw.text((30,795),'六位博主主题装束',fill='#382a24',font=font(27))
        for row,name in enumerate(NAMES):
            frame = atlas.crop((0,row*h,w,(row+1)*h))
            paste(board,frame,(40+row*180,840,155,200),True)
            draw.text((48+row*180,1050),name,fill='#382a24',font=font(21))
        draw.text((1140,730),'成果与结果页面',fill='#382a24',font=font(27))
        paste(board,Image.open(result),(1140,775,620,370))
        draw.text((30,1120),'局部UI与操作反馈',fill='#382a24',font=font(27))
        shot = Image.open(main)
        paste(board,shot.crop((0,int(shot.height*.68),shot.width,shot.height)),(30,1170,1080,215))
        note = entry.get('properties',{}).get('cultural_note','原角色像素衍生；文化资料与游戏化动作分别登记。')
        lines = [note[i:i+24] for i in range(0,len(note),24)]
        draw.multiline_text((1140,1180),'\n'.join(lines),fill='#705d4e',font=font(21),spacing=8)
        board.save(boards/f'{ident}.png')
    (ART/'presentation-manifest.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2),encoding='utf-8')
    notes = ['双辫与棕灰发；工艺关收起背包','半扎发与浅色发饰；保留发型结构','银卷发、胡须与成熟脸部；按主题换装','棕发侧结与活泼表情；帽饰按主题调整','灰短发与红色强调；户外装保留竹篓绑腿','金色挑染与较长发；不固定礼帽燕尾服']
    for ident,name,note in zip(IDS,NAMES,notes):
        board=Image.new('RGB',(1200,820),'#f3e7d1'); d=ImageDraw.Draw(board)
        d.text((40,25),name+'  身份设定',fill='#382a24',font=font(36))
        paste(board,Image.open(ART/f'runtime/identities/{ident}/preview.png'),(40,95,1120,640),True)
        d.text((40,760),note,fill='#382a24',font=font(25))
        board.save(boards/f'identity-{ident}.png')
    television = Image.new('RGB',(1800,1450),'#f3e7d1')
    d = ImageDraw.Draw(television)
    d.text((35,20),'木壳电视 · 真实控件与像素舞台分层',fill='#382a24',font=font(36))
    for i,(state,label) in enumerate([('prepare','准备与角色换装'),('scene','挑战与局部提示'),('miss','失误反馈'),('result','成果与结果')]):
        x,y=30+(i%2)*890,100+(i//2)*650
        d.text((x,y),label,fill='#382a24',font=font(25))
        paste(television,Image.open(REVIEW/f'xia_lian_dan_shu-travel-{state}.png'),(x,y+45,860,570))
    television.save(boards/'television-ui.png')
    overview = Image.new('RGB',(1600,1800),'#f3e7d1')
    d = ImageDraw.Draw(overview)
    d.text((25,15),'楚物志 · 十五关像素场景',fill='#382a24',font=font(32))
    for i,entry in enumerate(entries):
        text = (ROOT/'InheritanceTasks/Definitions'/f'{entry["task_id"]}.tres').read_text(encoding='utf-8')
        title = re.search(r'^heritage_name = "(.*)"', text, re.M)[1]
        x,y=20+(i%3)*530,80+(i//3)*340
        paste(overview,Image.open(local(entry['cover'])),(x,y,510,306),True)
        d.text((x,y+308),title,fill='#382a24',font=font(20))
    overview.save(boards/'fifteen-scenes.png')
    records=[]
    for p in sorted(ART.rglob('*')):
        if not p.is_file() or p.suffix in ['.import','.uid'] or p.name=='delivery-manifest.json': continue
        item={'path':p.relative_to(ROOT).as_posix(),'bytes':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
        if p.suffix=='.png':
            im=Image.open(p); item.update(size=list(im.size),mode=im.mode)
        item['role']='source' if 'source' in p.parts else ('review_board' if 'boards' in p.parts else 'runtime_or_metadata')
        records.append(item)
    (ART/'delivery-manifest.json').write_text(json.dumps({'version':1,'date':'2026-09-13','task_count':len(entries),'avatar_count':6,'user_visual_acceptance':'pending','files':records},ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Built {len(entries)} game boards/covers, six identity boards, and {len(records)} inventory records.')


if __name__ == '__main__': build()
