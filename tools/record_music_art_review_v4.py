"""Record actual source/scene checks separately from future animation approval."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v3'
NOTES = {
    'jingzhou_hua_gu_xi': ('红衣、青袖裤、花饰、团扇的独立主唱', '四个关键姿势，完整脸、双手、扇与双脚可见。', 4),
    'han_ju': ('红衣白水袖、蓝色头冠的独立演员', '八个走台与亮相关键姿势；并不代表已核对真实身段或完成流畅走台。', 8),
    'ti_qin_xi': ('紫衣、盘发与花饰的后景演员', '四个关键姿势；舞台绘制与封面均按新源帧宽高比显示，避免把脸压窄。', 4),
}

for task, (identity, note, count) in NOTES.items():
    source = ART / 'source' / task / 'npcs-r4-green.png'
    runtime = ART / 'runtime' / task / 'npcs.png'
    original, exported = Image.open(source), Image.open(runtime)
    record = dict(tool='built-in imagegen', revision='r4', source=source.name,
                  source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                  identity_reference='npcs.png: '+identity,
                  style_reference='本关旅行博主源图，仅用于头身与画法，不替换独立演员身份',
                  cultural_status='沿用已有参考服装设计；本次未新增真实戏服或身段考证',
                  source_size=list(original.size), exported_frame_size=[exported.width//count, exported.height],
                  source_alpha=original.mode=='RGBA', source_review=note,
                  export_review='保留原稿颜色和帧框，技术绿底转换；完整场景中未见棋盘格或明显绿边。',
                  whole_scene_review={'status':'reviewed', 'files':[f'artifacts/music-host-v4/{task}-teaching-1280.png'],
                                      'notes':'对照玩家、后景演员、舞台、教学顶条及器物，未把单张角色稿当整景完成。'},
                  normal_speed_review='pending', six_avatar_review='pending', user_accepted=False,
                  remaining='连续动作、帧间接缝、真实演出考证与用户画面反馈继续单独检查。')
    if task == 'jingzhou_hua_gu_xi':
        record['rejected_source'] = 'npcs-r4-rejected-checker.png'
        record['rejection_reason'] = 'RGB图画入了棋盘格，用imagegen改为纯技术绿底后才接入。'
    (source.parent / 'npcs-r4-provenance.json').write_text(json.dumps(record, ensure_ascii=False, indent=2)+'\n',encoding='utf-8')

pending = dict(task='ti_qin_xi', avatar='travel_blogger', user_accepted=False,
               attempts=[{'file':'travel-bow-r6-rejected.png', 'status':'rejected_not_integrated',
                          'reason':'琴弓明显随伸臂变长，不能作为连续运弓素材。'},
                         {'file':'travel-bow-r7-review.png','status':'not_integrated_needs_revision',
                          'reason':'弓长变化减小，但第一帧右弓尖越过分格边界；中间帧变化不均匀。'}],
               rule='不能用加帧数、拉长手臂、倒放同一方向或强制缩小掩盖结构缺陷。当前正式前景保留旧候选，尚未完成本轮长弓整改。')
(ART / 'source/ti_qin_xi/bow-revision-r6-r7.json').write_text(json.dumps(pending,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Recorded three whole-scene reviews and two unintegrated bow attempts.')
