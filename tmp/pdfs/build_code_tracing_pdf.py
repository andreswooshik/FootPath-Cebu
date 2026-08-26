from __future__ import annotations

import html
import re
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4, landscape
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfbase import pdfmetrics
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    KeepTogether,
    LongTable,
    PageBreak,
    PageTemplate,
    Paragraph,
    Preformatted,
    Spacer,
    Table,
    TableStyle,
)
from reportlab.platypus.tableofcontents import TableOfContents


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "docs" / "capstone-defense" / "16-code-tracing.md"
OUTPUT = ROOT / "output" / "pdf" / "footpath-cebu-code-tracing.pdf"

PAGE = landscape(A4)
PAGE_W, PAGE_H = PAGE
LEFT = RIGHT = 16 * mm
TOP = 19 * mm
BOTTOM = 16 * mm
CONTENT_W = PAGE_W - LEFT - RIGHT

NAVY = colors.HexColor("#102A43")
BLUE = colors.HexColor("#1769AA")
TEAL = colors.HexColor("#0E7490")
PALE_BLUE = colors.HexColor("#EAF4FB")
PALE_TEAL = colors.HexColor("#E8F6F8")
INK = colors.HexColor("#243B53")
MUTED = colors.HexColor("#627D98")
GRID = colors.HexColor("#CBD5E1")
ROW_ALT = colors.HexColor("#F6F9FC")


def register_fonts() -> tuple[str, str, str]:
    candidates = [
        (
            Path(r"C:\Windows\Fonts\segoeui.ttf"),
            Path(r"C:\Windows\Fonts\segoeuib.ttf"),
            Path(r"C:\Windows\Fonts\consola.ttf"),
        ),
        (
            Path(r"C:\Windows\Fonts\arial.ttf"),
            Path(r"C:\Windows\Fonts\arialbd.ttf"),
            Path(r"C:\Windows\Fonts\cour.ttf"),
        ),
    ]
    for regular, bold, mono in candidates:
        if regular.exists() and bold.exists() and mono.exists():
            pdfmetrics.registerFont(TTFont("DocSans", str(regular)))
            pdfmetrics.registerFont(TTFont("DocSansBold", str(bold)))
            pdfmetrics.registerFont(TTFont("DocMono", str(mono)))
            return "DocSans", "DocSansBold", "DocMono"
    return "Helvetica", "Helvetica-Bold", "Courier"


REGULAR, BOLD, MONO = register_fonts()


def normalize(value: str) -> str:
    replacements = {
        "\u2010": "-",
        "\u2011": "-",
        "\u2012": "-",
        "\u2013": "-",
        "\u2014": "-",
        "\u2192": "->",
        "\u2018": "'",
        "\u2019": "'",
        "\u201c": '"',
        "\u201d": '"',
        "\u2026": "...",
        "\u00b7": " | ",
        "\u2264": "<=",
        "\u2265": ">=",
        "\u2705": "[IMPLEMENTED]",
        "\u274c": "[NOT IMPLEMENTED]",
        "\U0001f7e1": "[PARTIAL]",
        "\u00a0": " ",
    }
    value = html.unescape(value)
    for old, new in replacements.items():
        value = value.replace(old, new)
    return value


def inline_markup(value: str) -> str:
    value = normalize(value)
    links: list[tuple[str, str]] = []

    def link_placeholder(match: re.Match[str]) -> str:
        links.append((match.group(1), match.group(2)))
        return f"@@LINK{len(links) - 1}@@"

    value = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", link_placeholder, value)
    codes: list[str] = []

    def code_placeholder(match: re.Match[str]) -> str:
        codes.append(match.group(1))
        return f"@@CODE{len(codes) - 1}@@"

    value = re.sub(r"`([^`]+)`", code_placeholder, value)
    value = html.escape(value)
    value = re.sub(
        r"\*\*([^*]+)\*\*",
        lambda match: f'<font name="{BOLD}">{match.group(1)}</font>',
        value,
    )
    value = re.sub(r"(?<!\*)\*([^*]+)\*(?!\*)", r"<i>\1</i>", value)
    for index, code in enumerate(codes):
        rendered = html.escape(normalize(code))
        value = value.replace(
            f"@@CODE{index}@@",
            f'<font name="{MONO}" color="#0E4F66">{rendered}</font>',
        )
    for index, (label, target) in enumerate(links):
        rendered = f"{html.escape(normalize(label))} ({html.escape(normalize(target))})"
        value = value.replace(f"@@LINK{index}@@", rendered)
    return value


base = getSampleStyleSheet()
styles = {
    "body": ParagraphStyle(
        "Body",
        parent=base["BodyText"],
        fontName=REGULAR,
        fontSize=9.1,
        leading=12.6,
        textColor=INK,
        spaceAfter=5,
        allowWidows=0,
        allowOrphans=0,
    ),
    "h1": ParagraphStyle(
        "H1",
        parent=base["Heading1"],
        fontName=BOLD,
        fontSize=19,
        leading=23,
        textColor=NAVY,
        spaceBefore=8,
        spaceAfter=9,
        keepWithNext=True,
    ),
    "h2": ParagraphStyle(
        "H2",
        parent=base["Heading2"],
        fontName=BOLD,
        fontSize=13.5,
        leading=17,
        textColor=BLUE,
        spaceBefore=10,
        spaceAfter=6,
        keepWithNext=True,
    ),
    "h3": ParagraphStyle(
        "H3",
        parent=base["Heading3"],
        fontName=BOLD,
        fontSize=10.5,
        leading=13,
        textColor=TEAL,
        spaceBefore=7,
        spaceAfter=4,
        keepWithNext=True,
    ),
    "bullet": ParagraphStyle(
        "Bullet",
        parent=base["BodyText"],
        fontName=REGULAR,
        fontSize=8.9,
        leading=12.2,
        leftIndent=12,
        firstLineIndent=-8,
        textColor=INK,
        spaceAfter=3,
    ),
    "quote": ParagraphStyle(
        "Quote",
        parent=base["BodyText"],
        fontName=REGULAR,
        fontSize=8.8,
        leading=12.2,
        leftIndent=10,
        rightIndent=8,
        borderColor=TEAL,
        borderWidth=1.5,
        borderPadding=(6, 8, 6, 8),
        backColor=PALE_TEAL,
        textColor=INK,
        spaceBefore=4,
        spaceAfter=7,
    ),
    "code": ParagraphStyle(
        "Code",
        fontName=MONO,
        fontSize=7.2,
        leading=9.2,
        leftIndent=7,
        rightIndent=7,
        borderColor=GRID,
        borderWidth=0.5,
        borderPadding=7,
        backColor=colors.HexColor("#F3F6F9"),
        textColor=colors.HexColor("#183B56"),
        spaceBefore=4,
        spaceAfter=7,
    ),
    "table": ParagraphStyle(
        "TableCell",
        fontName=REGULAR,
        fontSize=7.1,
        leading=9,
        textColor=INK,
    ),
    "table_head": ParagraphStyle(
        "TableHead",
        fontName=BOLD,
        fontSize=7.2,
        leading=9,
        textColor=colors.white,
    ),
}


class TracingDocTemplate(BaseDocTemplate):
    def __init__(self, filename: str):
        super().__init__(
            filename,
            pagesize=PAGE,
            leftMargin=LEFT,
            rightMargin=RIGHT,
            topMargin=TOP,
            bottomMargin=BOTTOM,
            title="FootPath Cebu - Deep Code Tracing",
            author="FootPath Cebu",
            subject="Verified code execution maps and security traces",
        )
        frame = Frame(LEFT, BOTTOM, CONTENT_W, PAGE_H - TOP - BOTTOM, id="body")
        self.addPageTemplates(PageTemplate(id="main", frames=[frame], onPage=self._page))

    def _page(self, canvas, doc):
        canvas.saveState()
        if doc.page > 1:
            canvas.setFillColor(NAVY)
            canvas.rect(0, PAGE_H - 12 * mm, PAGE_W, 12 * mm, fill=1, stroke=0)
            canvas.setFont(BOLD, 8.3)
            canvas.setFillColor(colors.white)
            canvas.drawString(LEFT, PAGE_H - 7.5 * mm, "FOOTPATH CEBU | DEEP CODE TRACING")
            canvas.setFont(REGULAR, 7.7)
            canvas.drawRightString(PAGE_W - RIGHT, PAGE_H - 7.5 * mm, "Updated: Match Performance Tracking")
        canvas.setStrokeColor(GRID)
        canvas.line(LEFT, 10.5 * mm, PAGE_W - RIGHT, 10.5 * mm)
        canvas.setFont(REGULAR, 7.4)
        canvas.setFillColor(MUTED)
        canvas.drawString(LEFT, 6.5 * mm, "Repository-backed defense reference | Commit db9e869")
        canvas.drawRightString(PAGE_W - RIGHT, 6.5 * mm, f"Page {doc.page}")
        canvas.restoreState()

    def afterFlowable(self, flowable):
        if isinstance(flowable, Paragraph):
            level = getattr(flowable, "toc_level", None)
            title = getattr(flowable, "toc_title", None)
            if level is not None and title:
                key = f"heading-{self.seq.nextf('heading')}"
                self.canv.bookmarkPage(key)
                # The source occasionally moves from an H1 directly to an H3.
                # PDF outlines require every intermediate level, so collapse
                # H2/H3 to one navigable child level while keeping TOC depth.
                self.canv.addOutlineEntry(title, key, level=min(level, 1), closed=False)
                self.notify("TOCEntry", (level, title, self.page, key))


def heading(text: str, level: int) -> Paragraph:
    paragraph = Paragraph(inline_markup(text), styles[f"h{level}"])
    if level <= 2:
        paragraph.toc_level = level - 1
        paragraph.toc_title = normalize(text)
    return paragraph


def parse_table(lines: list[str]) -> LongTable:
    raw_rows = []
    for line in lines:
        cells = [cell.strip() for cell in line.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{3,}:?", cell.replace(" ", "")) for cell in cells):
            continue
        raw_rows.append(cells)
    columns = max(len(row) for row in raw_rows)
    for row in raw_rows:
        row.extend([""] * (columns - len(row)))
    char_weights = []
    for column in range(columns):
        longest = max(len(normalize(row[column])) for row in raw_rows)
        char_weights.append(max(7, min(longest, 38)))
    total_weight = sum(char_weights)
    col_widths = [CONTENT_W * weight / total_weight for weight in char_weights]
    cooked = []
    for row_index, row in enumerate(raw_rows):
        style = styles["table_head"] if row_index == 0 else styles["table"]
        cooked.append([Paragraph(inline_markup(cell), style) for cell in row])
    table = LongTable(cooked, colWidths=col_widths, repeatRows=1, hAlign="LEFT")
    commands = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("GRID", (0, 0), (-1, -1), 0.35, GRID),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
        ("TOPPADDING", (0, 0), (-1, -1), 4),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
    ]
    for row_index in range(2, len(cooked), 2):
        commands.append(("BACKGROUND", (0, row_index), (-1, row_index), ROW_ALT))
    table.setStyle(TableStyle(commands))
    return table


def markdown_story(source: str) -> list:
    lines = source.splitlines()
    story: list = []
    paragraph_lines: list[str] = []
    code_lines: list[str] = []
    in_code = False
    index = 0

    def flush_paragraph():
        nonlocal paragraph_lines
        if paragraph_lines:
            text = " ".join(line.strip() for line in paragraph_lines)
            story.append(Paragraph(inline_markup(text), styles["body"]))
            paragraph_lines = []

    while index < len(lines):
        line = lines[index]
        if line.strip().startswith("```"):
            flush_paragraph()
            if in_code:
                code = normalize("\n".join(code_lines))
                story.append(Preformatted(code, styles["code"], maxLineLength=118))
                code_lines = []
                in_code = False
            else:
                in_code = True
            index += 1
            continue
        if in_code:
            code_lines.append(line)
            index += 1
            continue
        if line.startswith("|") and index + 1 < len(lines) and lines[index + 1].startswith("|"):
            flush_paragraph()
            table_lines = []
            while index < len(lines) and lines[index].startswith("|"):
                table_lines.append(lines[index])
                index += 1
            story.append(parse_table(table_lines))
            story.append(Spacer(1, 7))
            continue
        match = re.match(r"^(#{1,3})\s+(.+)$", line)
        if match:
            flush_paragraph()
            level = len(match.group(1))
            story.append(heading(match.group(2), level))
            index += 1
            continue
        bullet = re.match(r"^\s*[-*]\s+(.+)$", line)
        ordered = re.match(r"^\s*(\d+)\.\s+(.+)$", line)
        if bullet or ordered:
            flush_paragraph()
            if bullet:
                prefix, text = "-", bullet.group(1)
            else:
                prefix, text = f"{ordered.group(1)}.", ordered.group(2)
            story.append(Paragraph(f"{prefix} {inline_markup(text)}", styles["bullet"]))
            index += 1
            continue
        if line.startswith(">"):
            flush_paragraph()
            quote_lines = []
            while index < len(lines) and lines[index].startswith(">"):
                quote_lines.append(lines[index].lstrip("> "))
                index += 1
            story.append(Paragraph(inline_markup(" ".join(quote_lines)), styles["quote"]))
            continue
        if not line.strip():
            flush_paragraph()
            index += 1
            continue
        paragraph_lines.append(line)
        index += 1
    flush_paragraph()
    if code_lines:
        story.append(Preformatted(normalize("\n".join(code_lines)), styles["code"]))
    return story


def build() -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    source = SOURCE.read_text(encoding="utf-8")
    lines = source.splitlines()
    title = normalize(lines[0].removeprefix("# "))
    body = "\n".join(lines[1:])

    title_style = ParagraphStyle(
        "CoverTitle",
        fontName=BOLD,
        fontSize=31,
        leading=36,
        alignment=TA_LEFT,
        textColor=NAVY,
    )
    subtitle_style = ParagraphStyle(
        "CoverSubtitle",
        fontName=REGULAR,
        fontSize=14,
        leading=20,
        textColor=TEAL,
    )
    badge_style = ParagraphStyle(
        "Badge",
        fontName=BOLD,
        fontSize=10,
        leading=14,
        textColor=colors.white,
        alignment=TA_CENTER,
    )
    cover_box = Table(
        [[Paragraph("UPDATED FEATURE TRACE", badge_style)]],
        colWidths=[55 * mm],
        rowHeights=[11 * mm],
        style=TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), TEAL),
            ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
            ("BOX", (0, 0), (-1, -1), 0, TEAL),
        ]),
    )

    toc = TableOfContents()
    toc.levelStyles = [
        ParagraphStyle("TOC1", fontName=BOLD, fontSize=10, leading=14, leftIndent=0, textColor=NAVY, spaceBefore=4),
        ParagraphStyle("TOC2", fontName=REGULAR, fontSize=8.5, leading=11, leftIndent=14, textColor=INK),
        ParagraphStyle("TOC3", fontName=REGULAR, fontSize=7.6, leading=10, leftIndent=28, textColor=MUTED),
    ]

    story = [
        Spacer(1, 24 * mm),
        cover_box,
        Spacer(1, 13 * mm),
        Paragraph(html.escape(title), title_style),
        Spacer(1, 7 * mm),
        Paragraph(
            "Verified execution paths, authorization boundaries, database traces, "
            "failure handling, and defense-ready call chains.",
            subtitle_style,
        ),
        Spacer(1, 15 * mm),
        Table(
            [
                [Paragraph("Revision", styles["table_head"]), Paragraph("Merged match-performance tracking", styles["table"])],
                [Paragraph("Source commit", styles["table_head"]), Paragraph("db9e869 - feat: add secure match performance tracking", styles["table"])],
                [Paragraph("Verified suites", styles["table_head"]), Paragraph("271 Django tests | 250 Flutter tests | clean Flutter analysis | no migration drift", styles["table"])],
                [Paragraph("Primary audience", styles["table_head"]), Paragraph("Capstone defense, code review, and implementation tracing", styles["table"])],
            ],
            colWidths=[42 * mm, 145 * mm],
            style=TableStyle([
                ("BACKGROUND", (0, 0), (0, -1), NAVY),
                ("BACKGROUND", (1, 0), (1, -1), PALE_BLUE),
                ("GRID", (0, 0), (-1, -1), 0.5, GRID),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 7),
                ("RIGHTPADDING", (0, 0), (-1, -1), 7),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]),
        ),
        PageBreak(),
        heading("Contents", 1),
        toc,
        PageBreak(),
    ]
    story.extend(markdown_story(body))
    document = TracingDocTemplate(str(OUTPUT))
    document.multiBuild(story)
    print(f"WROTE {OUTPUT}")


if __name__ == "__main__":
    build()
