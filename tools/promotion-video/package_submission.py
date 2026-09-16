from pathlib import Path
import subprocess,os,zipfile,shutil,json,hashlib
R=Path(__file__).resolve().parents[2];D=R/'artifacts/submission-20260916';G=D/'game'
env=os.environ.copy();env['APPDATA']=str(D/'isolated-user');env['PROMO_RELEASE_CAPTURE']=str(D/'release-menu.png')
Path(env['APPDATA']).mkdir(exist_ok=True)
si=subprocess.STARTUPINFO();si.dwFlags|=subprocess.STARTF_USESHOWWINDOW;si.wShowWindow=1
with (D/'smoke.log').open('w',encoding='utf8') as log:
 p=subprocess.run([str(G/'楚物志.exe'),'--windowed','--resolution','1280x720','--quit-after','180'],cwd=G,env=env,stdout=log,stderr=subprocess.STDOUT,startupinfo=si,timeout=90)
text=(D/'smoke.log').read_text(encoding='utf8')
assert p.returncode==0 and 'OpenGL API' in text and 'SCRIPT ERROR' not in text and '\nERROR:' not in text,text[-4000:]
print('Release smoke passed',flush=True)
(G/'先读我.txt').write_text('楚物志 · 楚行九州\nWindows 64位参赛版\n\n请先完整解压，再运行“楚物志.exe”。请勿删除同目录的 PCK 或 DLL。\n\n开始游戏：本地对局或入门教学。支持本地玩家与三档电脑对手。\n图鉴：查看非遗、职业等内容，也可练习十五项传承小游戏。\n设置：声音、画面与辅助选项。局内 Esc 暂停。\n\n黄梅戏演唱挑战需要麦克风，其他内容无需麦克风。\n',encoding='utf-8-sig')
licenses=G/'第三方许可';licenses.mkdir(exist_ok=True)
for path in (R/'InheritanceTasks/AudioNative/licenses').rglob('*'):
 if path.is_file(): shutil.copy2(path,licenses/path.name)
for path in [R/'arts/ui-main-v1/fonts/sans-LICENSE.txt',R/'arts/ui-main-v1/fonts/serif-LICENSE.txt',R/'InheritanceTasks/Art/Pixel/v2/fonts/LICENSE-OFL.txt']:
 shutil.copy2(path,licenses/path.name)
out=R/'artifacts/promotion-2026/delivery/楚物志_楚行九州_Windows参赛版.zip'
with zipfile.ZipFile(out,'w',zipfile.ZIP_DEFLATED,compresslevel=1,allowZip64=True) as z:
 for path in sorted(G.rglob('*')):
  if path.is_file(): z.write(path,'楚物志/'+path.relative_to(G).as_posix())
print('ZIP created',out.stat().st_size,flush=True)
with zipfile.ZipFile(out) as z: assert z.testzip() is None
(D/'package-report.json').write_text(json.dumps({'zip':str(out),'bytes':out.stat().st_size,'sha256':hashlib.file_digest(out.open('rb'),'sha256').hexdigest(),'crc':'PASS','release_smoke':'PASS','full_beta_rerun':False},ensure_ascii=False,indent=2),encoding='utf8')
print('ZIP verified',flush=True)




