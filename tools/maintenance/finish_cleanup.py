"""Verify batch receipts before rebuilding caches; produce a readable inventory."""
from pathlib import Path
import csv,hashlib,json,struct
ROOT=Path(__file__).resolve().parents[2]
D=ROOT/'maintenance/cleanup-20260916'
manifest=json.loads((D/'frozen-manifest.json').read_text(encoding='utf8'))
receipts={r['original']:r for line in (D/'receipts.jsonl').read_text(encoding='utf-8-sig').splitlines() if line for r in [json.loads(line)]}
visible={p.lower() for p in json.loads((D/'shell-visible-final.json').read_text(encoding='utf-8-sig'))}
rows=[]
for entry in manifest:
    r=receipts[entry['path']]
    assert not Path(entry['path']).exists(), entry['path']
    assert r['shell_visible'] and r['all_file_hashes_match']
    assert r['verified_file_count']==entry['file_count'] and r['verified_bytes']==entry['bytes']
    assert Path(r['data']).exists() and r['data'].lower() in visible
    raw=Path(r['metadata']).read_bytes()
    version=struct.unpack_from('<q',raw)[0]
    original=raw[28 if version==2 else 24:].decode('utf-16le').rstrip('\0')
    assert original.lower()==entry['path'].lower()
    rows.append([entry['path'],r['data'],r['metadata'],entry['file_count'],entry['bytes'],r['deleted_utc'],'SHA-256全部一致'])
for item in json.loads((D/'preserved.json').read_text(encoding='utf8')):
    with Path(item['retained']).open('rb') as f:
        assert hashlib.file_digest(f,'sha256').hexdigest()==item['sha256'],item['retained']
with (D/'回收清单.csv').open('w',encoding='utf-8-sig',newline='') as f:
    w=csv.writer(f);w.writerow(['原始位置','回收数据位置','回收元数据位置','文件数','逻辑字节','回收UTC时间','内容核验']);w.writerows(rows)
summary=dict(targets=len(rows),files=sum(x['file_count'] for x in manifest),bytes=sum(x['bytes'] for x in manifest),receipts_valid=True,shell_visible=True,preserved_hashes_match=True,permanent_deletion_used=False,validation='recycle stage only; Beta/Release results recorded separately')
(D/'recycle-summary.json').write_text(json.dumps(summary,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(summary,ensure_ascii=False))
