"""Run candidate-only Aseprite prep and inspect the exact exported artifacts."""
from pathlib import Path
import hashlib
import json
import subprocess
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'InheritanceTasks/Art/Pixel/v2/review/generated-workshop'
EXE = Path('F:/Tools/Aseprite/chuwuzhi-v1.3.18.5/build/bin/aseprite.exe')
SOURCE = OUT / 'workshop-source-r1.png'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def run(args):
    result = subprocess.run([str(EXE), *map(str,args)],cwd=ROOT,capture_output=True,
                            text=True,encoding='utf-8',errors='replace')
    if result.returncode:
        raise RuntimeError(f'Aseprite failed ({result.returncode}): {result.stdout}\n{result.stderr}')
    return result.stdout + result.stderr

original_hash = sha(SOURCE)
log = run(['--batch','--script-param','root='+ROOT.as_posix(),'--script',ROOT/'tools/aseprite/prepare_workshop_review.lua'])
prep = json.loads((OUT/'preparation-report.json').read_text(encoding='utf-8'))
report = {'source_sha256':original_hash,'aseprite_sha256':sha(EXE),'status':'program checks only; candidate not approved',
          'log':log,'variants':[]}
for budget in (48,64):
    prefix = OUT/f'workshop-r1-{budget}'
    ase = prefix.with_suffix('.aseprite')
    png = prefix.with_suffix('.png')
    metadata = OUT/f'workshop-r1-{budget}-metadata.json'
    reopened = OUT/f'workshop-r1-{budget}-reopened.png'
    run(['--batch',ase,'--sheet-type','horizontal','--sheet',reopened,'--data',metadata,
         '--format','json-array','--list-layers','--list-tags','--list-slices'])
    art = Image.open(png).convert('RGBA')
    double = Image.open(OUT/f'workshop-r1-{budget}-2x.png').convert('RGBA')
    before = Image.open(OUT/f'workshop-r1-{budget}-before-cleanup.png').convert('RGBA')
    json_meta = json.loads(metadata.read_text(encoding='utf-8'))
    colors = set(art.get_flattened_data())
    changes = sum(a!=b for a,b in zip(art.get_flattened_data(),before.get_flattened_data()))
    expectations = {
        'native_size_500x300': art.size==(500,300),
        'preview_exact_nearest_2x': double.tobytes()==art.resize((1000,600),Image.Resampling.NEAREST).tobytes(),
        'visible_colors_within_budget': len(colors)<=budget,
        'fully_opaque_background': all(c[3]==255 for c in colors),
        'aseprite_reopen_exact': Image.open(reopened).convert('RGBA').tobytes()==art.tobytes(),
        'three_editable_layers': len(next(v['reopened_layers'] for v in prep['variants'] if v['color_budget']==budget))==3,
        'two_visible_export_layers': len(json_meta['meta']['layers'])==2,
        'six_placement_slices': len(json_meta['meta']['slices'])==6,
        'only_registered_cleanup_pixels_changed': changes==next(v['cleanup_count'] for v in prep['variants'] if v['color_budget']==budget),
    }
    if not all(expectations.values()): raise AssertionError(expectations)
    report['variants'].append({'budget':budget,'visible_colors':len(colors),'cleanup_pixels':changes,'checks':expectations,
        'files_sha256':{f.name:sha(f) for f in (ase,png,metadata,reopened,OUT/f'workshop-r1-{budget}-2x.png')}})
assert sha(SOURCE)==original_hash,'Original changed during preparation'
report['original_preserved']=True
(OUT/'program-validation.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'original_preserved':True,'variants':[{k:v[k] for k in ('budget','visible_colors','cleanup_pixels')} for v in report['variants']]}))
