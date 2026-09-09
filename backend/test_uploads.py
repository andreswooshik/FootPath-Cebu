"""Small, structurally valid upload fixtures shared by backend tests."""

from io import BytesIO

from PIL import Image
from pypdf import PdfWriter


def jpeg_bytes():
    output = BytesIO()
    Image.new('RGB', (2, 2), color=(25, 90, 60)).save(output, format='JPEG')
    return output.getvalue()


def pdf_bytes():
    output = BytesIO()
    writer = PdfWriter()
    writer.add_blank_page(width=72, height=72)
    writer.write(output)
    return output.getvalue()
