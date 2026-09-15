"""Update the teacher-facing scope without changing other UI requirements."""
from pathlib import Path
from shutil import copy2
from docx import Document

ROOT = Path(__file__).resolve().parents[1]
path = ROOT / 'docs/楚物志数字版美术需求书（精简版）.docx'
backup = ROOT / 'artifacts/art-brief-before-pixel-20260913.docx'
backup.parent.mkdir(exist_ok=True)
if not backup.exists(): copy2(path, backup)
doc = Document(path)
replacements = {
    '十五项小游戏采用细致16位像素风，人物三至四头身，外层使用木壳暖色老电视。小游戏内部画布为500×300，对应1000×600逻辑舞台；中文、按钮和结果信息独立清晰绘制。该风格仅用于传承任务，桌游主界面继续沿用本需求书的整体方向。':
    '十五项小游戏采用卡通、二次元像素画，人物严格保留六位原博主的身份，外层使用木壳暖色老电视。人物、器物、动作与背景由开发侧直接生成并整理；保留原稿清晰度，按实际镜头确定尺寸，不强制缩成低分辨率或少量颜色。中文、按钮和结果信息独立清晰绘制；桌游主体继续沿用本需求书的整体方向。',
    '美术老师仅需确保桌游外层的非遗详情、小游戏图鉴入口和传承成功后的“？→5”反馈能够连接现有流程，不需重画电视框体、小游戏背景或十五套人物动作。小游戏制作清单与状态另见《传承小游戏像素重构与验收记录（2026-09-13）》及工程资产台账。':
    '美术老师仅需确保桌游外层的非遗详情、小游戏图鉴入口和传承成功后的“？→5”反馈能够连接现有流程，不需重画电视框体、小游戏背景或十五套人物动作。当前小游戏制作与验证状态见《传承小游戏第三版生成资产与全面实施（2026-09-14）》及工程资产台账。',
    '主界面与开局流程、局内界面、教程与规则手册都要完善。新版首页背景、Logo和常用图标单独制作；投骰子及必要的卡牌、移动、资源反馈补齐。15项传承任务的全套美术也在范围内，本版只列素材范围，具体造型以后逐项讨论。':
    '本需求书由美术老师负责的范围为主界面与开局流程、局内界面、教程与规则手册，以及新版首页背景、Logo、常用图标、投骰子和必要的卡牌、移动、资源反馈。2026年9月13日起，十五项传承小游戏的全套场景、人物、装束、动画、器物、封面及小游戏UI/UX统一由GPT‑6负责制作、整理和接入，不再计入美术老师交付量。',
    '交付：图鉴网格、筛选标签与勾选、翻页、已发现／未发现卡位、空结果、图片放大层。小游戏条目复用这些组件，缩略图要求见第七节。':
    '交付：图鉴网格、筛选标签与勾选、翻页、已发现／未发现卡位、空结果、图片放大层。小游戏图鉴可复用外层组件；十五张小游戏封面及角色选择、挑战弹窗由GPT‑6提供。',
    '七 传承任务（优先级：5/5）': '七 传承任务由开发侧制作',
    '共用界面与素材要求': '责任与风格边界',
    '15项小游戏都需要完整美术，但本版只确认素材范围，人物造型、文化元素、关卡物件数量及具体帧数留待逐项讨论。下表是制作清单，不是要求立即照白模定稿；未经确认不新增复杂角色或机关。':
    '十五项小游戏采用细致16位像素风，人物三至四头身，外层使用木壳暖色老电视。小游戏内部画布为500×300，对应1000×600逻辑舞台；中文、按钮和结果信息独立清晰绘制。该风格仅用于传承任务，桌游主界面继续沿用本需求书的整体方向。',
    '任务共用封面、目标与操作提示、开始、倒计时或进度、暂停、退出确认、成功、失败原因和技术错误界面。游玩时提示退到边缘，不遮判定区域；成功返回局内时连接“？→5”解锁，图鉴重玩只显示本次结果。':
    'GPT‑6负责电视框体、准备、教学、挑战、暂停、结果和技术错误页面，以及六位博主身份设定、逐关换装、人物动作、场景、器物、局部提示、封面与资产台账。原有博主图片保留，新像素角色作为独立衍生资源；正式挑战跟随本局职业，练习可选角色。',
    '交付共用宿主排版和切片、状态图标、结果样式及缩略图模板。每项另交背景、可独立移动的物件、必要动画和640×400缩略图；缩略图突出核心动作，不烘焙任务名或按钮。':
    '美术老师仅需确保桌游外层的非遗详情、小游戏图鉴入口和传承成功后的“？→5”反馈能够连接现有流程，不需重画电视框体、小游戏背景或十五套人物动作。小游戏制作清单与状态另见《传承小游戏像素重构与验收记录（2026-09-13）》及工程资产台账。',
    '舞台基准1600×1000，四周约8%安全区；物件一般用最长边512或1024的透明图。判定线、碰撞范围、歌词、计时和分数不画进背景，线条可交皮肤，由程序绘制。安全／危险、命中／失误同时用形状或符号区分。':
    '用户提供已授权完整视频即可。开发侧负责选段、抽帧、提取音频和来源记录；鼓盆歌鼓板演唱、西塞神舟全貌与送舟、鄂州雕花剪纸刻制近景仍需补充资料。待核对的器物形制与游戏化动作在台账中明确标注。',
}
for paragraph in doc.paragraphs:
    if paragraph.text in replacements: paragraph.text = replacements[paragraph.text]
    elif paragraph.text == '15项任务素材范围': paragraph.text = '资料补充与接入'
    # The original contents list used static page numbers; keep a truthful outline.
    elif '\t' in paragraph.text and paragraph.text.rsplit('\t', 1)[-1].isdigit():
        paragraph.text = paragraph.text.rsplit('\t', 1)[0].replace('15项任务素材范围', '资料补充与接入').replace('共用界面与素材要求', '责任与风格边界')
for table in list(doc.tables):
    if table.cell(0, 0).text == '非遗与任务' or '15项' in table.cell(0, 0).text or '传承任务' in table.cell(0, 0).text:
        table._element.getparent().remove(table._element)
    else:
        for row in list(table.rows):
            if row.cells[0].text == '小游戏':
                table._element.remove(row._tr)
for paragraph in list(doc.paragraphs):
    if paragraph.text in ['资料补充与接入', '音频与文化资料']:
        paragraph._element.getparent().remove(paragraph._element)
    elif paragraph.text == '七 传承任务': paragraph.text = '七 传承任务由开发侧制作'
doc.save(path)
print(path)
