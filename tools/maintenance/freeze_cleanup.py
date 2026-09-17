"""Freeze per-file evidence. Refuse reparse points and protected paths."""
from pathlib import Path
import hashlib,json,os,stat,subprocess
ROOT=Path(__file__).resolve().parents[2]
RECORD=ROOT/'maintenance/cleanup-20260916'
if (RECORD/'receipts.jsonl').exists():
    raise RuntimeError('Recycling has started; never refreeze recreated paths.')
tracked=set(subprocess.check_output(['git','ls-files','-z'],cwd=ROOT).decode('utf8').split('\0'))
candidates=json.loads((RECORD/'candidates.json').read_text(encoding='utf8'))
roots=[Path(c['path']) for c in candidates]
result=[];exceptions=[];identities={};total=0
for c in candidates:
    p=Path(c['path'])
    if not p.exists(): raise ValueError(f'Missing: {p}')
    if any(parent in roots for parent in p.parents): continue
    rel=p.relative_to(ROOT)
    if rel.parts[0] in ('.git','deliverables','maintenance') or p==ROOT:raise ValueError(p)
    files=[];dirs=[];unsafe=False
    if p.is_dir():
        for base, ds, fs in os.walk(p,followlinks=False):
            for name in ds+fs:
                q=Path(base)/name
                if q.lstat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:unsafe=True
            dirs.extend(str((Path(base)/name).relative_to(p)) for name in ds)
            files.extend(Path(base)/name for name in fs)
    else: files=[p]
    if p.lstat().st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT:unsafe=True
    if unsafe:
        exceptions.append(dict(path=str(p),reason='Contains reparse point; not traversed or recycled'))
        continue
    entries=[]
    for f in sorted(files):
        s=f.stat(); key=(s.st_dev,s.st_ino)
        with f.open('rb') as stream: sha=hashlib.file_digest(stream,'sha256').hexdigest()
        entries.append(dict(relative=str(f.relative_to(p)) if p.is_dir() else '',bytes=s.st_size,mtime_ns=s.st_mtime_ns,sha256=sha,tracked=f.relative_to(ROOT).as_posix() in tracked))
        identities[key]=s.st_size
    count=sum(e['bytes'] for e in entries);total+=count
    result.append(dict(**c,kind='directory' if p.is_dir() else 'file',file_count=len(entries),bytes=count,directories=sorted(dirs),files=entries,reference_check='Transient artifact/dependency/cache, or consolidated dated report. Protected deliverables and evidence hashes in preserved.json.'))
(RECORD/'frozen-manifest.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
(RECORD/'exceptions.json').write_text(json.dumps(exceptions,ensure_ascii=False,indent=2),encoding='utf8')
(RECORD/'totals.json').write_text(json.dumps(dict(targets=len(result),files=sum(x['file_count'] for x in result),logical_bytes=total,unique_file_identity_bytes=sum(identities.values()),exceptions=exceptions),ensure_ascii=False,indent=2),encoding='utf8')
print(f'{len(result)} roots, {total/2**30:.3f} GiB logical, {sum(identities.values())/2**30:.3f} GiB unique identities; {len(exceptions)} exceptions')
