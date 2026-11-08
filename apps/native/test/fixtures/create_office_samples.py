"""Small independent Office fixtures for attachment preview acceptance."""
from io import BytesIO
from zipfile import ZipFile, ZIP_DEFLATED
from xml.etree import ElementTree as ET
from pathlib import Path
from PIL import Image, ImageDraw
from docx import Document
from docx.shared import Inches
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill
from pptx import Presentation
from pptx.util import Inches as SlideInches, Pt
from pptx.dml.color import RGBColor

root = Path(__file__).parent
image = Image.new('RGB', (320, 160), '#166534')
draw = ImageDraw.Draw(image)
draw.rectangle((20, 20, 145, 140), fill='#38bdf8')
draw.ellipse((175, 20, 295, 140), fill='#fbbf24')
buffer = BytesIO()
image.save(buffer, format='PNG')
picture = buffer.getvalue()

doc = Document()
doc.add_heading('Nekodot 文件预览', 0)
doc.add_paragraph('中文与 English：保留标题、粗体、图片和表格。')
doc.add_paragraph('Important content', style='Heading 1')
doc.add_paragraph('The source document remains unchanged.').runs[0].bold = True
doc.add_picture(BytesIO(picture), width=Inches(3))
table = doc.add_table(rows=1, cols=2)
table.style = 'Light Shading Accent 1'
table.rows[0].cells[0].text = '项目 / Item'
table.rows[0].cells[1].text = '数量 / Count'
row = table.add_row().cells
row[0].text, row[1].text = '文件', '42'
doc.add_page_break()
doc.add_heading('第二页 / Second page', 1)
doc.add_paragraph('End of document — 667.')
doc.save(root / 'preview.docx')

book = Workbook()
sheet = book.active
sheet.title = '用量 Usage'
sheet.append(['项目', '输入', '输出', '合计'])
sheet.append(['Dot A', 1200, 400, '=SUM(B2:C2)'])
sheet.append(['Dot B', 800, 600, '=SUM(B3:C3)'])
sheet.append(['总计', '=SUM(B2:B3)', '=SUM(C2:C3)', '=SUM(D2:D3)'])
for cell in sheet[1]:
    cell.font = Font(color='FFFFFF', bold=True)
    cell.fill = PatternFill('solid', fgColor='166534')
for col in 'ABCD':
    sheet.column_dimensions[col].width = 19
sheet.freeze_panes = 'B2'
sheet['B6'], sheet['B7'] = 0.125, 1234.5
sheet['B6'].number_format = '0.0%'
sheet['B7'].number_format = '#,##0.00'
sheet['A9'], sheet['B9'] = 'Saved Excel result', '=_xlfn.XLOOKUP(A2,A2:A3,B2:B3)'
details = book.create_sheet('明细 Details')
details.append(['Second sheet', '中文明细'])
details.append(['Result', 667])
book.save(root / 'preview.xlsx')
# Match a workbook last saved by Excel: openpyxl does not calculate formulas.
# Include an unsupported function with a saved result to verify read-only
# preview does not replace the source value with a recalculation error.
path = root / 'preview.xlsx'
with ZipFile(path) as archive:
    parts = {name: archive.read(name) for name in archive.namelist()}
ns = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
xml = ET.fromstring(parts['xl/worksheets/sheet1.xml'])
for cell in xml.iter(ns + 'c'):
    cached = {'D2': 1600, 'D3': 1400, 'B4': 2000, 'C4': 1000, 'D4': 3000, 'B9': 1200}
    if cell.get('r') in cached:
        cell.find(ns + 'v').text = str(cached[cell.get('r')])
parts['xl/worksheets/sheet1.xml'] = ET.tostring(xml, encoding='utf-8')
with ZipFile(path, 'w', ZIP_DEFLATED) as archive:
    for name, data in parts.items():
        archive.writestr(name, data)

deck = Presentation()
deck.slide_width, deck.slide_height = SlideInches(13.333), SlideInches(7.5)
for number, title in enumerate(['办公预览 / Office preview', '第二页 / Second slide'], 1):
    slide = deck.slides.add_slide(deck.slide_layouts[6])
    slide.background.fill.solid()
    slide.background.fill.fore_color.rgb = RGBColor.from_string('F1F5F9')
    box = slide.shapes.add_textbox(SlideInches(.6), SlideInches(.5), SlideInches(12), SlideInches(1))
    run = box.text_frame.paragraphs[0].add_run()
    run.text, run.font.size, run.font.bold = title, Pt(32), True
    slide.shapes.add_picture(BytesIO(picture), SlideInches(.8), SlideInches(2), width=SlideInches(5))
    table = slide.shapes.add_table(3, 2, SlideInches(7), SlideInches(2), SlideInches(5), SlideInches(2.5)).table
    for row, values in enumerate([['项目 / Item', '数值'], ['Slide', str(number)], ['23 × 29', '667']]):
        for col, value in enumerate(values):
            table.cell(row, col).text = value
    slide.shapes.add_textbox(SlideInches(.8), SlideInches(6), SlideInches(11), SlideInches(.7)).text = 'Original layout · images · tables · 中文'
deck.save(root / 'preview.pptx')
(root / 'preview.md').write_text('# Markdown 文件预览\n\n**中文粗体**与 English。\n\n| 项目 | 数值 |\n| --- | ---: |\n| 23 × 29 | 667 |\n\n- 文件不会自动发送\n- 保留原始附件\n', encoding='utf-8')
print('Created DOCX, XLSX, PPTX and Markdown fixtures')
