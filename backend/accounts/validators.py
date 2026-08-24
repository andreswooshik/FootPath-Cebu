"""Validation shared by every coach-license upload surface."""

import os

from django.core.exceptions import ValidationError


COACH_LICENSE_MAX_BYTES = 50 * 1024 * 1024  # 50 MB
COACH_LICENSE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.pdf'}
COACH_LICENSE_CONTENT_TYPES = {
    'image/jpeg',
    'image/png',
    'application/pdf',
}
COACH_LICENSE_SIGNATURES = (
    b'\xff\xd8\xff',          # JPEG
    b'\x89PNG\r\n\x1a\n',   # PNG
    b'%PDF-',                 # PDF
)


def validate_coach_license_upload(upload):
    """Accept only genuine JPG, PNG, or PDF documents up to 50 MB.

    The extension and browser-provided MIME type are not sufficient security
    checks, so the first bytes are verified as well. Existing committed
    ``FieldFile`` values are skipped because they were validated when uploaded.
    """
    if getattr(upload, '_committed', False):
        return

    extension = os.path.splitext(getattr(upload, 'name', ''))[1].lower()
    if extension not in COACH_LICENSE_EXTENSIONS:
        raise ValidationError('Upload a JPG, PNG or PDF file.')

    content_type = getattr(upload, 'content_type', None)
    if content_type and content_type not in COACH_LICENSE_CONTENT_TYPES:
        raise ValidationError('Unsupported file type. Use JPG, PNG or PDF.')

    if getattr(upload, 'size', 0) > COACH_LICENSE_MAX_BYTES:
        raise ValidationError('The file must be 50 MB or smaller.')

    try:
        upload.seek(0)
        header = upload.read(8)
        upload.seek(0)
    except (AttributeError, OSError) as exc:
        raise ValidationError('The uploaded document could not be read.') from exc

    if not any(header.startswith(signature) for signature in COACH_LICENSE_SIGNATURES):
        raise ValidationError(
            'That file does not look like a real JPG, PNG or PDF.'
        )
