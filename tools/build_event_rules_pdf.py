from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import PageBreak, Paragraph, SimpleDocTemplate, Spacer


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs" / "随机事件（数字版）.md"
OUTPUT = ROOT / "docs" / "随机事件（数字版）.pdf"


def register_cjk_font() -> str:
    candidates = [
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf"),
        Path("C:/Windows/Fonts/simsun.ttc"),
    ]
    for candidate in candidates:
        if candidate.exists():
            pdfmetrics.registerFont(TTFont("CWZ-CJK", str(candidate), subfontIndex=0))
            return "CWZ-CJK"
    raise FileNotFoundError("未找到可用于数字版规则 PDF 的中文字体。")


def inline_markup(text: str) -> str:
    escaped = html.escape(text)
    return re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", escaped)


def draw_page(canvas, doc) -> None:
    canvas.saveState()
    canvas.setFont("CWZ-CJK", 8.5)
    canvas.setFillColor(colors.HexColor("#666666"))
    canvas.drawString(18 * mm, A4[1] - 12 * mm, "《楚物志》随机事件 - 数字版规则")
    canvas.drawRightString(A4[0] - 18 * mm, 11 * mm, f"第 {doc.page} 页")
    canvas.setStrokeColor(colors.HexColor("#B8B1A5"))
    canvas.line(18 * mm, A4[1] - 14 * mm, A4[0] - 18 * mm, A4[1] - 14 * mm)
    canvas.restoreState()


def build() -> None:
    font = register_cjk_font()
    base = getSampleStyleSheet()
    styles = {
        "title": ParagraphStyle(
            "CWZTitle", parent=base["Title"], fontName=font, fontSize=22,
            leading=30, alignment=TA_CENTER, textColor=colors.HexColor("#2F3438"), spaceAfter=14,
        ),
        "h2": ParagraphStyle(
            "CWZH2", parent=base["Heading2"], fontName=font, fontSize=15,
            leading=21, textColor=colors.HexColor("#37474F"), spaceBefore=8, spaceAfter=5,
            keepWithNext=True,
        ),
        "body": ParagraphStyle(
            "CWZBody", parent=base["BodyText"], fontName=font, fontSize=9.8,
            leading=15.2, alignment=TA_LEFT, textColor=colors.HexColor("#222222"),
            spaceAfter=3.5, wordWrap="CJK",
        ),
        "bullet": ParagraphStyle(
            "CWZBullet", parent=base["BodyText"], fontName=font, fontSize=9.8,
            leading=15.2, leftIndent=8 * mm, firstLineIndent=-4 * mm, bulletIndent=2 * mm,
            spaceAfter=3, wordWrap="CJK",
        ),
    }

    story = []
    for raw_line in SOURCE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line:
            story.append(Spacer(1, 1.5 * mm))
            continue
        if line.startswith("# "):
            story.append(Paragraph(inline_markup(line[2:]), styles["title"]))
        elif line.startswith("## "):
            story.append(Paragraph(inline_markup(line[3:]), styles["h2"]))
        elif line.startswith("- "):
            story.append(Paragraph(inline_markup(line[2:]), styles["bullet"], bulletText="•"))
        else:
            story.append(Paragraph(inline_markup(line.rstrip("  ")), styles["body"]))

    document = SimpleDocTemplate(
        str(OUTPUT), pagesize=A4, rightMargin=18 * mm, leftMargin=18 * mm,
        topMargin=19 * mm, bottomMargin=17 * mm,
        title="《楚物志》随机事件 - 数字版规则",
        author="《楚物志》项目组",
    )
    document.build(story, onFirstPage=draw_page, onLaterPages=draw_page)
    print(OUTPUT)


if __name__ == "__main__":
    build()
