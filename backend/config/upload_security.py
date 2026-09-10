"""Central, fail-closed validation and sanitization for user uploads."""

from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError
from pypdf import PdfReader, PdfWriter

MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 25_000_000

_IMAGE_FORMATS = {
    'image/jpeg': ('JPEG', 'JPEG'),
    'image/png': ('PNG', 'PNG'),
    'image/webp': ('WEBP', 'WEBP'),
}
_DANGEROUS_PDF_MARKERS = (
    b'/JavaScript',
    b'/JS',
    b'/OpenAction',
    b'/AA',
    b'/Launch',
    b'/EmbeddedFiles',
    b'/RichMedia',
    b'/XFA',
)


def read_limited_upload(upload, *, max_bytes=MAX_UPLOAD_BYTES):
    """Read an upload without trusting its caller-controlled size metadata."""
    if getattr(upload, 'size', 0) > max_bytes:
        raise ValueError('The file must be 5 MB or smaller.')
    try:
        upload.seek(0)
        content = upload.read(max_bytes + 1)
        upload.seek(0)
    except (AttributeError, OSError) as exc:
        raise ValueError('The uploaded file could not be read.') from exc
    if len(content) > max_bytes:
        raise ValueError('The file must be 5 MB or smaller.')
    if not content:
        raise ValueError('The uploaded file is empty.')
    return content


def sanitize_image(content, content_type):
    """Fully decode and re-encode one still image, stripping metadata/trailing data."""
    expected_format, output_format = _IMAGE_FORMATS.get(content_type, (None, None))
    if expected_format is None:
        raise ValueError('Unsupported image type.')
    try:
        Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS
        with Image.open(BytesIO(content)) as candidate:
            if candidate.format != expected_format:
                raise ValueError('The uploaded file does not match its image type.')
            if candidate.width * candidate.height > MAX_IMAGE_PIXELS:
                raise ValueError('The uploaded image dimensions are too large.')
            if getattr(candidate, 'n_frames', 1) != 1:
                raise ValueError('Animated images are not allowed.')
            candidate.verify()
        with Image.open(BytesIO(content)) as decoded:
            decoded.load()
            decoded = ImageOps.exif_transpose(decoded)
            if output_format == 'JPEG' and decoded.mode not in ('RGB', 'L'):
                decoded = decoded.convert('RGB')
            output = BytesIO()
            save_options = {'optimize': True}
            if output_format == 'JPEG':
                save_options['quality'] = 90
            decoded.save(output, format=output_format, **save_options)
    except (UnidentifiedImageError, OSError, SyntaxError) as exc:
        raise ValueError('The uploaded image is corrupt or unsafe.') from exc
    sanitized = output.getvalue()
    if len(sanitized) > MAX_UPLOAD_BYTES:
        raise ValueError('The processed image is larger than 5 MB.')
    return sanitized


def sanitize_pdf(content):
    """Parse and rewrite a passive PDF, rejecting scripts and embedded content."""
    if not content.startswith(b'%PDF-'):
        raise ValueError('The uploaded file does not match its PDF type.')
    if any(marker in content for marker in _DANGEROUS_PDF_MARKERS):
        raise ValueError('Active or embedded PDF content is not allowed.')
    try:
        reader = PdfReader(BytesIO(content), strict=True)
        if reader.is_encrypted:
            raise ValueError('Encrypted PDF files are not allowed.')
        writer = PdfWriter()
        for source_page in reader.pages:
            writer.add_page(source_page)
            page = writer.pages[-1]
            # Annotations can launch links/actions; schedules and licenses do
            # not need them, so remove them from the sanitized copy.
            if '/Annots' in page:
                del page['/Annots']
        output = BytesIO()
        writer.write(output)
    except ValueError:
        raise
    except Exception as exc:
        raise ValueError('The uploaded PDF is corrupt or unsafe.') from exc
    sanitized = output.getvalue()
    if not sanitized.startswith(b'%PDF-') or not reader.pages:
        raise ValueError('The uploaded PDF must contain at least one page.')
    if len(sanitized) > MAX_UPLOAD_BYTES:
        raise ValueError('The processed PDF is larger than 5 MB.')
    return sanitized


def sanitize_document(content, content_type):
    if content_type == 'application/pdf':
        return sanitize_pdf(content)
    return sanitize_image(content, content_type)
