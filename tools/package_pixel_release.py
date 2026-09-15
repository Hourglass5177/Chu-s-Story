"""Package an already verified Release and editable pixel assets; never exports."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v1'


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for block in iter(lambda: f.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--game-dir', type=Path, required=True)
    parser.add_argument('--verification', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    game = args.game_dir.resolve(strict=True)
    verification = args.verification.resolve(strict=True)
    checked = json.loads((verification/'release-check-summary.json').read_text(encoding='utf-8'))
    if checked.get('status') != 'PASS':
        raise RuntimeError('Release verification must pass before packaging')
    exe, pck = game/'楚物志.exe', game/'楚物志.pck'
    if checked['exe_sha256'] != sha(exe) or checked['pck_sha256'] != sha(pck):
        raise RuntimeError('The Release changed after verification')
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    release = output/'楚物志-像素重构验收版-20260913.zip'
    brief = ROOT/'docs/楚物志数字版美术需求书（精简版）.docx'
    report = ROOT/'docs/传承小游戏像素重构与验收记录（2026-09-13）.md'
    readme = '''楚物志 · 像素重构验收版（2026-09-13）

解压整个ZIP后，进入“楚物志 Windows版”运行“楚物志.exe”。
请保留同目录PCK和DLL，不要只复制EXE。

主菜单 → 图鉴 → 小游戏可练习十五关并选择六位博主。
正式对局的角色随当前玩家职业；小游戏设置可重学、调音量和视觉辅助。
七关已认可玩法保留，新画面及重做关仍待实际试玩反馈。

本包含精简美术需求书。十五关全部美术与小游戏UI由GPT-6负责，
已从美术老师工作量中移出。

待核对：鼓盆歌鼓板与原声、神舟全貌和送舟、鄂州雕花剪纸刻制近景。
五个重做音乐关全段谱面仍待逐句听审。详情见附带验收记录。
本次验证没有开启真实麦克风录制。
'''
    with ZipFile(release, 'w', ZIP_DEFLATED, compresslevel=6) as z:
        for path in sorted(game.rglob('*')):
            if path.is_file(): z.write(path, '楚物志 Windows版/'+path.relative_to(game).as_posix())
        z.write(brief, brief.name)
        z.write(report, report.name)
        z.writestr('先读我.txt', readme)
        for name in ['release-check-summary.json','resource-model-report.json']:
            z.write(verification/name, '验证记录/'+name)
    source = output/'楚物志-像素素材与动画源包-20260913.zip'
    roots = [ART, ROOT/'InheritanceTasks/Presentation', ROOT/'InheritanceTasks/Data']
    scripts = ['build_pixel_assets.py','build_craft_pixel_assets.py','build_music_pixel_assets.py',
               'build_motion_pixel_assets.py','build_pixel_resources.py','build_pixel_delivery.py',
               'build_motion_covers.py','build_reviewed_performance_covers.py',
               'build_tiqin_bow_layers.py']
    source_readme = '''可编辑像素素材与动画资源（2026-09-13）

InheritanceTasks/Art/Pixel/v1/source：原始生成PNG、替换前版本、提示词与来源记录。
runtime：透明切片、动作图集、器物、分镜及封面；resources：Godot表现与SpriteFrames。
boards：六身份设定板、十五关检查板、电视母版与场景总览。
presentation-manifest.json：可编辑的十五关资产与动作索引；delivery-manifest.json：哈希台账。
Presentation和Data为对应表现层代码；tools为切片、锚点和资源生成脚本。

源图为PNG与图集，并非分层PSD。运行资源按角色/器物/场景分层，
动画由SpriteFrames和独立舞台脚本组合。需完整楚物志工程才能运行游戏。
美术状态为引擎内检查完成、用户新画面验收待定；形制与听审待办见验收记录。
'''
    with ZipFile(source, 'w', ZIP_DEFLATED, compresslevel=6) as z:
        for directory in roots:
            for path in sorted(directory.rglob('*')):
                if path.is_file() and path.suffix not in ['.import', '.pyc']:
                    z.write(path,path.relative_to(ROOT).as_posix())
        for name in scripts:
            z.write(ROOT/'tools'/name,'tools/'+name)
        z.write(report,'docs/'+report.name)
        z.writestr('素材编辑说明.txt',source_readme)
    records=[]
    for path in [release,source]:
        with ZipFile(path) as z:
            bad=z.testzip()
            if bad: raise RuntimeError(f'Corrupt ZIP member: {bad}')
            count=len(z.infolist())
        records.append({'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path),'entries':count})
    (output/'package-manifest.json').write_text(json.dumps(records,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(records,ensure_ascii=False,indent=2))


if __name__=='__main__': main()
