"""Normalize generated sources and record gameplay geometry; never redraw identities."""
from pathlib import Path
import sys
import hashlib, json, shutil
import cv2
import numpy as np
from PIL import Image, ImageOps

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/'InheritanceTasks/Art/Pixel/v3'
RECORDS=[]
IDS=['travel','life','business','food','adventure','magic']
GODOT_IDS=['travel_blogger','life_blogger','business_blogger','food_blogger','adventure_blogger','magic_blogger']

def key_green(im):
    rgba=np.array(im.convert('RGBA')); rgb=rgba[:,:,:3].astype(float)
    if im.mode!='RGBA' or rgba[:,:,3].min()==255:
        green=(rgb[:,:,1]>80)&(rgb[:,:,1]>rgb[:,:,0]*1.28+12)&(rgb[:,:,1]>rgb[:,:,2]*1.28+12)
        rgba[:,:,3]=np.where(green,0,255)
    else: rgba[:,:,3]=np.where(rgba[:,:,3]>=128,255,0)
    rgba[rgba[:,:,3]==0,:3]=0
    return Image.fromarray(rgba)

def palette(im,colors=32):
    alpha=im.getchannel('A')
    out=im.convert('RGB').quantize(colors=colors,dither=Image.Dither.NONE).convert('RGBA')
    out.putalpha(alpha)
    return out

def emit(im,path,source,method):
    path=BASE/'runtime'/path;path.parent.mkdir(parents=True,exist_ok=True);im.save(path)
    RECORDS.append({'file':str(path.relative_to(ROOT)).replace('\\','/'),'source':str(source.relative_to(ROOT)).replace('\\','/'),'size':list(im.size),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'method':method})

def components(im,count):
    mask=(np.array(im.getchannel('A'))>0).astype('uint8')
    n,labels,stats,centers=cv2.connectedComponentsWithStats(mask,8)
    chosen=sorted(range(1,n),key=lambda i:stats[i,4],reverse=True)[:count]
    out=[]
    for i in chosen:
        x,y,w,h,_=stats[i];crop=im.crop((x,y,x+w,y+h));a=np.array(crop)
        a[:,:,3]=np.where(labels[y:y+h,x:x+w]==i,255,0)
        out.append((tuple(centers[i]),Image.fromarray(a),(int(x),int(y),int(w),int(h))))
    return out

def normalized_component(im,height=None,width=None,size=None):
    if size: return im.resize(size,Image.Resampling.NEAREST)
    scale=height/im.height if height else width/im.width
    return im.resize((max(1,round(im.width*scale)),max(1,round(im.height*scale))),Image.Resampling.NEAREST)

def copy_sources():
    manifest=BASE/'source/action-assets-manifest.json'
    data=json.loads(manifest.read_text(encoding='utf-8'))
    for entry in data['entries']:
        folder='paper' if entry['id'].startswith('paper_') else 'dong'
        dest=BASE/'source'/folder/(entry['id']+'.png');dest.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(entry['source'],dest);entry['workspace_source']=str(dest.relative_to(ROOT))
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')

def write_dong_contact_anchors():
    """Measure effective opaque joint centers; grip is a separately reviewed point."""
    # Individually reviewed sleeve ends; generated upper-arm components differ
    # substantially. In particular the adventure source has a short sleeve.
    sleeve_end={'travel_blogger':.70,'life_blogger':.61,'business_blogger':.84,
                'food_blogger':.58,'adventure_blogger':.36,'magic_blogger':.76}
    for avatar in GODOT_IDS:
        folder=BASE/'runtime/dong'/avatar
        path=folder/'anchors.json'
        data=json.loads(path.read_text(encoding='utf8'))
        joints={}
        for part in ['upper-arm','forearm']:
            im=Image.open(folder/(part+'.png')); a=np.array(im.getchannel('A'))>0
            h,w=a.shape
            endpoints=[]
            # Upper-arm source includes a spare bare-wrist cap. Its actual
            # elbow socket is the sleeve above that cap; forearm owns the cuff.
            cap=sleeve_end[avatar]
            end_band=(round(h*(cap-.11)),round(h*(cap-.04))) if part=='upper-arm' else (round(h*.85),h)
            for lo,hi in [(0,max(2,round(h*.12))),end_band]:
                ys,xs=np.where(a[lo:hi,:])
                endpoints.append([float(xs.mean()),float(ys.mean()+lo)])
            joints[part]={'start':endpoints[0],'end':endpoints[1],
                          'display_width':15.0 if part=='upper-arm' else 12.5,
                          'clip_end_y':round(h*cap) if part=='upper-arm' else h}
            axis=np.array(endpoints[1])-np.array(endpoints[0]);axis=axis/np.linalg.norm(axis)
            ys,xs=np.where(a[:joints[part]['clip_end_y'],:])
            across=xs*(-axis[1])+ys*axis[0]
            joints[part]['opaque_cross_width']=float(across.max()-across.min())
        im=Image.open(folder/'hand.png'); a=np.array(im.getchannel('A'))>0
        h,w=a.shape; ys,xs=np.where(a[:,:max(2,round(w*.12))])
        joints['hand']={'wrist':[float(xs.mean()),float(ys.mean())],
                        'grip':[w*.70,h*.49], 'display_height':16.0}
        joints['torso']={'near_shoulder_uv':[.22,.27],'far_shoulder_uv':[.80,.23]}
        data['contact_joints']=joints
        data['contact_note']='Palm wrist and grip are independent. Forearm ends on opaque wrist opening; do not aim at grip or texture center. Bone endpoints use opaque joint centroids. Arm width stays fixed when the shoulder moves; only the longitudinal axis stretches. The upper-arm spare bare cap is clipped before overlapping the forearm sleeve.'
        path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf8')

def build_dong():
    for short,avatar in zip(IDS,GODOT_IDS):
        source=BASE/'source/dong'/('travel_green.png' if short=='travel' else short+'.png')
        im=key_green(Image.open(source))
        parts=components(im,8)
        # The reviewed sheets have four upper assets and four lower limbs.
        upper=sorted([p for p in parts if p[0][1]<im.height*.61],key=lambda p:p[0][0])
        lower=sorted([p for p in parts if p[0][1]>=im.height*.61],key=lambda p:p[0][0])
        assert len(upper)==4 and len(lower)==4,(avatar,[(p[0],p[2]) for p in parts])
        names=['reference','head','torso','hand','upper-arm','forearm','thigh','shin']
        anchors={'version':4,'source_size':list(im.size),'scaling':'source RGBA retained; display sizes live in the stage, not in destructively resized PNGs'}
        for name,part in zip(names,upper+lower):
            x,y,w,h=part[2]
            # Preserve every pixel within the reviewed object's bounds. Do not
            # keep only one connected component and discard detached highlights.
            native=im.crop((x,y,x+w,y+h))
            emit(native,Path('dong')/avatar/(name+'.png'),source,'full-resolution generated RGBA crop; green matte only; no quantization or resize')
            if name=='head':
                mask=np.array(native.getchannel('A'));ys,xs=np.where(mask[-max(3,round(h*.1)):,:]>0)
                anchors['neck']=[float(np.mean(xs)) if len(xs) else native.width*.6,native.height-1]
            anchors[name+'_source_bounds']=part[2]
        (BASE/'runtime/dong'/avatar/'anchors.json').write_text(json.dumps(anchors,indent=2),encoding='utf-8')
    source=BASE/'source/dong/dong_background.png'
    emit(Image.open(source).convert('RGBA'),Path('dong/background.png'),source,'original generated resolution and colors retained')
    source=BASE/'source/dong/props_green.png';im=key_green(Image.open(source))
    parts=components(im,5);parts=sorted(parts,key=lambda p:p[0][1])
    upper=sorted(parts[:2],key=lambda p:p[0][0]);lower=sorted(parts[2:],key=lambda p:p[0][0])
    for name,part in zip(['cart','father','wheel','blanket','bundle'],upper+lower):
        x,y,w,h=part[2]
        emit(im.crop((x,y,x+w,y+h)),Path('dong')/(name+'.png'),source,'full original prop crop with all rim/spokes and details; matte only, no resize/quantization')
    # Cart shaft is an existing generated wood crop, used between contact anchors.
    shaft=im.crop((160,334,420,361))
    emit(shaft,Path('dong/shaft.png'),source,'full resolution generated timber crop; rendered along exact handle anchor')
    source=BASE/'source/dong/ground.png';im=key_green(Image.open(source))
    parts=sorted(components(im,3),key=lambda p:p[0][1])
    for name,part in zip(['ground','bridge','rail'],parts):
        x,y,w,h=part[2]
        emit(im.crop((x,y,x+w,y+h)),Path('dong')/(name+'.png'),source,'original generated terrain crop; no resize/quantization; world-anchored display')
    bridge=BASE/'runtime/dong/bridge.png'
    anchor={'version':4,'source_image_size':list(Image.open(bridge).size),
            'source_sha256':hashlib.sha256(bridge.read_bytes()).hexdigest(),
            'surface_y_px':68,'logical_height':32,
            'note':'Upper walking face ends at source row 68, before the dark vertical front face starts at row 70. Align this contact edge to physical road height, not the PNG top border.'}
    (BASE/'runtime/dong/bridge-anchors.json').write_text(json.dumps(anchor,ensure_ascii=False,indent=2)+'\n',encoding='utf8')
    write_dong_contact_anchors()

def build_paper():
    source=BASE/'source/paper/paper_background.png'
    emit(palette(Image.open(source).convert('RGBA').resize((500,300),Image.Resampling.NEAREST),32),Path('paper/background.png'),source,'500x300 native palette normalization')
    source=BASE/'source/paper/paper_pattern.png';im=Image.open(source).convert('RGB').resize((340,210),Image.Resampling.NEAREST)
    rgb=np.array(im);white=(rgb[:,:,0]>190)&(rgb[:,:,1]>170)&(rgb[:,:,2]>150)
    n,labels,stats,centers=cv2.connectedComponentsWithStats(white.astype('uint8'),8)
    # Enclosed holes from the final generated pattern, not a line painted over it.
    selected=[]
    for target in [(82,99),(169,52),(248,102)]:
        options=[i for i in range(1,n) if stats[i,4]>150 and stats[i,0]>0 and stats[i,1]>0 and stats[i,0]+stats[i,2]<340 and stats[i,1]+stats[i,3]<210]
        best=min(options,key=lambda i:(centers[i][0]-target[0])**2+(centers[i][1]-target[1])**2)
        assert best not in selected;selected.append(best)
    contours=[]
    for i in selected:
        masks=(labels==i).astype('uint8');raw=cv2.findContours(masks,cv2.RETR_EXTERNAL,cv2.CHAIN_APPROX_SIMPLE)[0][0]
        # Keep pixel-accurate shape; simplify subpixel jitter only.
        contour=cv2.approxPolyDP(raw,.7,True).reshape(-1,2).tolist()
        start=min(range(len(contour)),key=lambda j:contour[j][0]+contour[j][1])
        contour=contour[start:]+contour[:start];contour.append(contour[0])
        contours.append([[160+x*2,112+y*2] for x,y in contour])
    data={'version':3,'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'paper_rect':[160,112,680,420],'contours':contours,'names':['左鸟翅羽','花心花瓣','右鸟翅羽'],'note':'Original generated game pattern; contours extracted from its three enclosed holes. Not a verified traditional artisan template.'}
    (ROOT/'InheritanceTasks/Data/paper-cut-geometry-v3.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf-8')
    # White backing becomes the same wax color; the three active holes are
    # covered/uncovered at runtime with the exact polygons above.
    rgb[white]=[68,54,47]
    out=Image.fromarray(rgb).convert('RGBA')
    emit(palette(out,12),Path('paper/pattern.png'),source,'three active hole contours extracted as gameplay geometry; backing mapped to wax mat')
    source=BASE/'source/paper/paper_hands.png';im=palette(key_green(Image.open(source)),24)
    parts=components(im,6);parts.sort(key=lambda p:(round(p[0][1]/im.height),p[0][0]))
    for avatar,part in zip(GODOT_IDS,parts):
        emit(normalized_component(part[1],height=54),Path('paper')/(avatar+'-hand.png'),source,'six sleeve variants; blade-tip crop is input anchor')

def build_boat():
    source=BASE/'source/shenzhou/river.png'
    emit(palette(Image.open(source).convert('RGBA').resize((500,300),Image.Resampling.NEAREST),32),Path('shenzhou/background.png'),source,'500x300 native,32-color background')
    source=BASE/'source/shenzhou/obstacles.png';im=palette(key_green(Image.open(source)),24)
    for index,name in enumerate(['boat','small-boat','driftwood']):
        crop=im.crop((index*im.width//3,0,(index+1)*im.width//3,im.height));crop=crop.crop(crop.getbbox())
        native=ImageOps.contain(crop,(64,28),Image.Resampling.NEAREST)
        emit(native,Path('shenzhou')/('obstacle-'+name+'.png'),source,'native RGBA preserved, separate ordinary boat/wood sprites, nearest contain')

if __name__=='__main__':
    if '--dong-contact-anchors' in sys.argv:
        write_dong_contact_anchors()
        print('Updated six original-RGBA wrist/grip/arm contact anchors only.')
        sys.exit(0)
    if '--only-dong' in sys.argv:
        build_dong()
        previous=json.loads((BASE/'action-art-manifest.json').read_text(encoding='utf8'))
        RECORDS=[r for r in previous['assets'] if '/runtime/dong/' not in r['file']]+RECORDS
    else:
        copy_sources();build_dong();build_paper();build_boat()
    (BASE/'action-art-manifest.json').write_text(json.dumps({'version':4,'assets':RECORDS,'acceptance':'generated candidate; full-detail Dong export v4; engine and user review separately recorded'},ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps({'assets':len(RECORDS),'status':'saved'},ensure_ascii=False))
