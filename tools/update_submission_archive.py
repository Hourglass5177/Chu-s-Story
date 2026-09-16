"""Replace only the nested Windows ZIP after checking all other member bytes."""
from pathlib import Path
import hashlib,json,os,shutil,subprocess,zipfile

ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'artifacts/credits-submission'
GAME=WORK/'game'
ARCHIVE=Path('F:/Desktop/楚物志.7z')
ZIP_NAME='楚物志_楚行九州_Windows参赛版.zip'
SEVEN=WORK/'toolchain/x64/7za.exe'
BACKUP=WORK/'original-楚物志.7z'
EDIT=WORK/'updated-楚物志.7z'

def sha(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()

def command(args,log,cwd=None):
    with (WORK/log).open('w',encoding='utf8') as f:
        subprocess.run([str(x) for x in args],cwd=cwd,stdout=f,stderr=subprocess.STDOUT,check=True)

def listing(path):
    output=subprocess.check_output([str(SEVEN),'l','-slt','-sccUTF-8',str(path)]).decode('utf8')
    records={}
    for block in output.split('----------',1)[1].strip().split('\n\n'):
        fields=dict(line.split(' = ',1) for line in block.splitlines() if ' = ' in line)
        if 'Path' in fields: records[fields['Path']]=fields
    return records

assert ARCHIVE.resolve()==Path('F:/Desktop/楚物志.7z').resolve()
assert not BACKUP.exists() and not EDIT.exists(), 'Preserve previous backup; choose a fresh work directory.'
original_sha=sha(ARCHIVE)
before=listing(ARCHIVE)
assert set(name for name in before if name.endswith('.zip'))=={ZIP_NAME}
shutil.copy2(ARCHIVE,BACKUP)
assert sha(BACKUP)==original_sha
shutil.copy2(BACKUP,EDIT)
original=WORK/'original-members';original.mkdir()
command([SEVEN,'x','-y',BACKUP,'-o'+str(original)],'extract-original.log')
hashes={name:sha(original/name) for name in before}
print('Backup and original member hashes recorded',flush=True)

env=os.environ.copy();env['APPDATA']=str(WORK/'isolated-user');Path(env['APPDATA']).mkdir(exist_ok=True)
si=subprocess.STARTUPINFO();si.dwFlags|=subprocess.STARTF_USESHOWWINDOW;si.wShowWindow=1
with (WORK/'release-startup.log').open('w',encoding='utf8') as log:
    result=subprocess.run([str(GAME/'楚物志.exe'),'--windowed','--resolution','1280x720','--quit-after','180'],cwd=GAME,env=env,stdout=log,stderr=subprocess.STDOUT,startupinfo=si,timeout=90)
log=(WORK/'release-startup.log').read_text(encoding='utf8')
assert result.returncode==0 and 'OpenGL API' in log and 'SCRIPT ERROR' not in log and '\nERROR:' not in log
print('Release startup passed',flush=True)

old_game=ROOT/'artifacts/submission-20260916/game'
shutil.copy2(old_game/'先读我.txt',GAME/'先读我.txt')
shutil.copytree(old_game/'第三方许可',GAME/'第三方许可',dirs_exist_ok=True)
stage=WORK/'replacement';stage.mkdir()
newzip=stage/ZIP_NAME
with zipfile.ZipFile(newzip,'w',zipfile.ZIP_DEFLATED,compresslevel=1) as z:
    for path in sorted(GAME.rglob('*')):
        if path.is_file(): z.write(path,'楚物志/'+path.relative_to(GAME).as_posix())
with zipfile.ZipFile(newzip) as z: assert z.testzip() is None
print('New Windows ZIP verified',flush=True)
command([SEVEN,'u','-y','-mx=1','-ms=off',EDIT,ZIP_NAME],'update-archive.log',stage)
command([SEVEN,'t',EDIT],'test-archive.log')
after=listing(EDIT)
assert set(before)==set(after), 'Archive member set changed'
verified=WORK/'verified-members';verified.mkdir()
command([SEVEN,'x','-y',EDIT,'-o'+str(verified)],'extract-verified.log')
for name in before:
    if name==ZIP_NAME: continue
    assert sha(verified/name)==hashes[name], 'Unexpected content change: '+name
    for key in ['Size','Modified','Attributes','CRC']:
        assert before[name].get(key)==after[name].get(key), 'Unexpected metadata change: '+name+' '+key
assert sha(verified/ZIP_NAME)==sha(newzip)
assert sha(ARCHIVE)==original_sha, 'Desktop archive changed during work; do not overwrite'
# Both absolute destinations are explicit; replace only this requested archive.
os.replace(EDIT,ARCHIVE)
report={'archive':str(ARCHIVE),'archive_sha256':sha(ARCHIVE),'backup':str(BACKUP),'backup_sha256':original_sha,'replaced_member':ZIP_NAME,'new_zip_sha256':sha(newzip),'other_members_unchanged':{name:hashes[name] for name in hashes if name!=ZIP_NAME},'startup':'PASS','zip_crc':'PASS','7z_integrity':'PASS','full_beta_rerun':False}
(WORK/'archive-update-report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print('DONE: desktop archive replaced; all five other files and their metadata unchanged.',flush=True)
