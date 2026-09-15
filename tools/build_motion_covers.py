"""Crop four reviewed motion-game covers from existing engine captures.

This only extracts/resizes already-rendered pixels. It does not generate art,
run the game, modify gameplay state, or certify human playtest acceptance.
"""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / 'InheritanceTasks/Art/Pixel/v1/runtime'
CASES = {
    'yandi_shennong_chuanshuo': {
        'source': 'artifacts/motion-pixel-play/yandi_shennong_chuanshuo.png',
        'crop': [360, 340, 1360, 940],
        'evidence': 'ordinary-input run, captured just after challenge time 12 s',
        'composition': 'Airborne player, cliff edge and next landing; crop excludes HUD.',
    },
    'dong_yong_chuanshuo': {
        'source': 'artifacts/pixel-art-review/dong_yong_chuanshuo-travel-pixel.png',
        'crop': [45, 65, 395, 275],
        'evidence': 'engine visual-state sample, not a normal-input pass record',
        'composition': 'Whole player, hands, cart and father; no obsolete bridge rendering.',
    },
    'xingshan_min_ge': {
        'source': 'artifacts/motion-pixel-play/xingshan_min_ge.png',
        'crop': [210, 190, 1460, 940],
        'evidence': 'ordinary-input run, captured just after challenge time 12 s',
        'composition': 'Lead bird and flock crossing an open gate, with village and fields.',
    },
    'xisai_shenzhou_hui': {
        'source': 'artifacts/motion-pixel-play/xisai_shenzhou_hui.png',
        'crop': [360, 230, 1560, 950],
        'evidence': 'ordinary-input run, captured just after challenge time 12 s',
        'composition': 'Whole pavilion boat, pinwheel and wake, centered in the river.',
    },
}


def build():
    sources, covers = ART / 'cover-source', ART / 'covers'
    sources.mkdir(parents=True, exist_ok=True)
    covers.mkdir(parents=True, exist_ok=True)
    records = []
    for ident, config in CASES.items():
        path = ROOT / config['source']
        picture = Image.open(path).convert('RGBA')
        left, top, right, bottom = config['crop']
        assert 0 <= left < right <= picture.width
        assert 0 <= top < bottom <= picture.height
        assert (right-left)*3 == (bottom-top)*5
        crop = picture.crop((left, top, right, bottom))
        cover = crop.resize((500, 300), Image.Resampling.NEAREST)
        for target in [sources / f'{ident}.png', covers / f'{ident}.png']:
            cover.save(target)
        records.append({'task_id': ident, **config,
                        'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                        'cover_sha256': hashlib.sha256((covers / f'{ident}.png').read_bytes()).hexdigest(),
                        'size': [500, 300], 'resample': 'nearest',
                        'human_playtest_acceptance': 'pending'})
    (sources / 'motion-cover-sources.json').write_text(
        json.dumps({'version': 1, 'date': '2026-09-13', 'covers': records},
                   ensure_ascii=False, indent=2), encoding='utf-8')
    print('Wrote four 500x300 covers and their reviewed source copies.')


if __name__ == '__main__':
    build()
