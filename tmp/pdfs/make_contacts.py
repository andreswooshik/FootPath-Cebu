from pathlib import Path
import math
from PIL import Image, ImageDraw


pages = sorted(Path("tmp/pdfs/rendered-v2").glob("page-*.png"))
output = Path("tmp/pdfs/contact-v2")
output.mkdir(parents=True, exist_ok=True)
thumb_w, thumb_h = 400, 283
columns, rows = 4, 4
batch = columns * rows

for sheet_index in range(math.ceil(len(pages) / batch)):
    chunk = pages[sheet_index * batch : (sheet_index + 1) * batch]
    sheet = Image.new("RGB", (columns * thumb_w, rows * thumb_h), "#d9e2ec")
    draw = ImageDraw.Draw(sheet)
    for index, page_path in enumerate(chunk):
        image = Image.open(page_path).convert("RGB")
        image.thumbnail((thumb_w - 8, thumb_h - 24))
        x = (index % columns) * thumb_w + 4
        y = (index // columns) * thumb_h + 20
        sheet.paste(image, (x, y))
        draw.text((x + 4, y - 16), page_path.stem, fill="black")
    sheet.save(output / f"contact-{sheet_index + 1:02}.png")

print(f"contacts {math.ceil(len(pages) / batch)}")
