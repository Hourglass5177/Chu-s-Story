"""Build a reviewed cleanup allowlist and preserve final deliverables. No deletion."""
from pathlib import Path
import hashlib
import json
import shutil

ROOT = Path(__file__).resolve().parents[2]
RECORD = ROOT / "maintenance/cleanup-20260916"
RECORD.mkdir(parents=True, exist_ok=True)
if (RECORD/'receipts.jsonl').exists():
    raise RuntimeError('Recycling has started; do not overwrite this batch evidence.')

def digest(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

preserved = []
def preserve(src, dst):
    src, dst = ROOT / src, ROOT / dst
    if not src.is_file():
        raise FileNotFoundError(src)
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() and digest(src) != digest(dst):
        raise ValueError(f'Destination differs: {dst}')
    shutil.copy2(src, dst)
    assert digest(src) == digest(dst)
    preserved.append(dict(source=str(src), retained=str(dst), bytes=src.stat().st_size, sha256=digest(dst)))

preserve('artifacts/credits-submission/replacement/楚物志_楚行九州_Windows参赛版.zip', 'deliverables/楚物志_楚行九州_Windows参赛版.zip')
for name in ['楚物志_楚行九州_参赛宣传视频_1分58秒.mp4', '楚物志_宣传图_1920x1080.png']:
    preserve('artifacts/promotion-2026/delivery/' + name, 'deliverables/' + name)
for p in (ROOT/'artifacts/promotion-2026/字幕文案_主体玩法版').iterdir():
    if p.is_file():
        preserve(str(p.relative_to(ROOT)), 'tools/promotion-video/final-captions/'+p.name)
preserve('artifacts/promotion-2026/shots-submit-118/timeline.json', 'tools/promotion-video/final-timeline.json')
for src in ['credits-submission/archive-update-report.json', 'recycle-verified-receipts.json', 'recycle-shell-visible.json', 'recycle-targets-reviewed.json']:
    preserve('artifacts/'+src, 'docs/verification/historical/'+Path(src).name)
for src in ['ai-phase-move-v4/closeout.json', 'ai-phase-move-v4/source-hashes.json', 'ai-next-stage/phase-move-repro.json', 'ai-next-stage/phase-move-repro.log', 'ai-next-stage/repro-241.log', 'ai-next-stage/phase-move-ai-tests.log']:
    preserve('artifacts/'+src, 'docs/verification/ai-v4/'+Path(src).name)
for p in (ROOT/'artifacts/ai-phase-move-v4/snapshot/artifacts/ai-v4-matrix').iterdir():
    if p.is_file():
        preserve(str(p.relative_to(ROOT)), 'docs/verification/ai-v4/matrix/'+p.name)
for p in (ROOT/'artifacts/ai-phase-move-v4/snapshot/artifacts/ai-traces').rglob('*.json'):
    preserve(str(p.relative_to(ROOT)), 'docs/verification/ai-v4/traces/'+p.name)
for p in [ROOT/'deliverables/.gdignore', ROOT/'maintenance/.gdignore']:
    p.write_text('', encoding='utf-8')
(RECORD/'preserved.json').write_text(json.dumps(preserved,ensure_ascii=False,indent=2),encoding='utf-8')

candidates=[]
def candidate(p, reason, replacement):
    p=Path(p)
    if p.exists():
        candidates.append(dict(path=str(p.resolve()), reason=reason, replacement=replacement))
for p in (ROOT/'artifacts').iterdir():
    if p.name in ['.gdignore', 'media-20260909', 'cleanup-validation']:
        continue
    candidate(p,'历史录制、快照、构建、审稿或诊断产物；必要最终结果已保全', 'deliverables/; docs/verification/; tools/promotion-video/')
for rel in ['tools/promotion-video/remotion/node_modules','tools/promotion-video/remotion/public','tools/promotion-video/sample-10s.mp4','.godot/imported','.godot/shader_cache']:
    candidate(ROOT/rel, '可重建依赖、媒体副本或导入缓存', '依赖锁文件、生成源及正式资源')
for p in (ROOT/'docs').glob('*.md'):
    if '（2026-' in p.name:
        candidate(p,'阶段记录已收敛至现状文档；历史版本仍在Git', 'docs/项目现状与已知问题.md; docs/verification/')
for rel in ['docs/传承任务原型素材替换清单.md','docs/传承小游戏体验复盘与重设计（2026-09-10）.md']:
    candidate(ROOT/rel,'已被当前实现替代的原型计划','docs/项目现状与已知问题.md')
unique={c['path']:c for c in candidates}
(RECORD/'candidates.json').write_text(json.dumps(list(unique.values()),ensure_ascii=False,indent=2),encoding='utf-8')
print(f'Preserved {len(preserved)} files; {len(unique)} candidate roots. No files recycled.')
