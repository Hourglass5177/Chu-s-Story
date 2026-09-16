"""Import the selected September delivery without changing the artist's originals."""
from pathlib import Path
import hashlib
import json
import shutil
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SOURCE = Path(r'E:\大学\MEMO\桌游 · 楚物志\新版素材\现有素材')
DEST = ROOT / 'arts' / 'ui-main-v1'
FILES = {
    'home': '03_主界面与开局/开启界面/拆分部件/背景（正常）v001.png',
    'logo': '01_品牌与Logo/彩色logov2.png',
    'loading_logo': '01_品牌与Logo/彩色logov1.png',
    'panel': '04_局内界面/卡牌详情/界面底版.png',
    'content': '04_局内界面/卡牌详情/右上文本框.png',
    'card': '04_局内界面/商店背包研究所/食物商店/食物底框.png',
    'guide_panel': '05-教程与图鉴/指南（原型）/教程底版.png',
    'guide_content': '05-教程与图鉴/指南（原型）/正文底版.png',
    'guide_sidebar': '05-教程与图鉴/指南（原型）/章节底版.png',
    'chapter': '05-教程与图鉴/指南（原型）/未选中章节.png',
    'chapter_selected': '05-教程与图鉴/指南（原型）/选中章节.png',
    'close': '02_通用UI/按钮/UI按钮图标_独立PNG/05_关闭_危险操作.png',
    'guide': '02_通用UI/按钮/UI按钮图标_独立PNG/03_指南.png',
    'pause': '02_通用UI/按钮/UI按钮图标_独立PNG/04_暂停.png',
    'back': '02_通用UI/按钮/UI按钮图标_独立PNG/06_返回.png',
}
HUD = '03_主界面与开局/主界面（AI）/PNG/'
for key, name in {
    'hud_background':'01_山水背景', 'hud_left':'03_左侧底板',
    'hud_name':'06_姓名框', 'hud_resource':'09_数值框',
    'money':'10_金币图标', 'energy':'11_体力图标',
    'hud_top':'12_顶部底板', 'hud_right':'21_右侧底板',
    'hud_score':'23_总分框', 'hud_bottom':'24_底部底板',
}.items():
    FILES[key] = HUD + name + '.png'
for kind, stem in [('primary','primary_large'),('secondary','secondary'),('danger','danger')]:
    for state in ['normal','hover','pressed','disabled']:
        rel = f'02_通用UI/按钮/ui_button_{stem}_{state}_v003.png'
        if (SOURCE / rel).exists():
            FILES[f'{kind}_{state}'] = rel
for i in range(1,7):
    FILES[f'dice_{i}'] = f'06_动画特效(仅有贴图)/骰子/立体效果/vfx_dice_face_{i}_v003.png'
for key in ['shadow','landing_ring']:
    FILES['dice_'+key] = f'06_动画特效(仅有贴图)/骰子/立体效果/vfx_dice_{key}_v001.png'
for key in ['heritage','event','work','shop','scenery','research']:
    FILES['ring_'+key] = f'06_动画特效(仅有贴图)/反馈特效/vfx_hex_ring_{key}_v003.png'
for key,stem in [('map_current','current_v002'),('map_target','target_v003'),('map_reachable','reachable_v003'),('map_route','route_dot_v002')]:
    FILES[key] = f'04_局内界面/地图提示/ui_map_{stem}.png'

FILES.update({
 'detail_card_frame':'04_局内界面/卡牌详情/卡牌底框.png',
 'detail_header':'04_局内界面/卡牌详情/顶部新事件.png',
 'detail_strip':'04_局内界面/卡牌详情/关闭.png',
 'shop_header':'04_局内界面/商店背包研究所/食物商店/标题栏.png',
 'balance_banner':'04_局内界面/商店背包研究所/食物商店/余额栏.png',
 'refresh':'04_局内界面/商店背包研究所/食物商店/刷新.png',
 'hud_map_frame':HUD+'02_地图卷轴.png',
 'hud_portrait_frame':HUD+'05_头像圆底.png',
 'hud_profession':HUD+'07_职业框.png',
 'hud_card_slot':HUD+'22_卡牌槽.png',
 'hud_bottom_content':HUD+'25_底部内容框.png',
 'hud_action':HUD+'26_金色按钮.png',
 'hud_action_disabled':HUD+'27_浅色按钮.png',
})

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    manifest = []
    for key, rel in FILES.items():
        src, out = SOURCE / rel, DEST / (key+'.png')
        shutil.copyfile(src, out)
        manifest.append({'id':key, 'source':str(src), 'runtime':str(out.relative_to(ROOT)),
                         'sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
    fonts = DEST / 'fonts'
    fonts.mkdir(exist_ok=True)
    for family, short in [('sans','Sans'),('serif','Serif')]:
        for weight in (['Regular','Bold'] if family == 'sans' else ['SemiBold']):
            name = f'SourceHan{short}SC-{weight}.otf'
            url = f'https://raw.githubusercontent.com/adobe-fonts/source-han-{family}/release/OTF/SimplifiedChinese/{name}'
            if not (fonts/name).exists(): urllib.request.urlretrieve(url, fonts/name)
        url = f'https://raw.githubusercontent.com/adobe-fonts/source-han-{family}/master/LICENSE.txt'
        urllib.request.urlretrieve(url, fonts/f'{family}-LICENSE.txt')
    (DEST/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'Imported {len(manifest)} selected images; originals preserved.')

if __name__ == '__main__': main()

