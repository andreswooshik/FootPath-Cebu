"""Validation shared by every coach-license upload surface."""

import os

from django.core.exceptions import ValidationError
from django.core.files.uploadedfile import SimpleUploadedFile

from config.upload_security import (
    MAX_UPLOAD_BYTES,
    read_limited_upload,
    sanitize_document,
)


COACH_LICENSE_MAX_BYTES = MAX_UPLOAD_BYTES
COACH_LICENSE_EXTENSIONS = {'.jpg', '.jpeg', '.png', '.pdf'}
COACH_LICENSE_CONTENT_TYPES = {
    'image/jpeg',
    'image/png',
    'application/pdf',
}
def validate_coach_license_upload(upload):
    """Accept only fully parsed JPG, PNG, or passive PDF files up to 5 MB.

    Extension and browser-provided MIME type are not sufficient security
    checks, so the full document is decoded and inspected. Existing committed
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

    try:
        content = read_limited_upload(upload)
        sanitize_document(
            content,
            content_type or _content_type_from_extension(extension),
        )
    except ValueError as exc:
        raise ValidationError(str(exc)) from exc


def _content_type_from_extension(extension):
    return {
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.png': 'image/png',
        '.pdf': 'application/pdf',
    }[extension]


def sanitized_coach_license(upload):
    """Return a metadata-free upload after the field validator has accepted it."""
    extension = os.path.splitext(getattr(upload, 'name', ''))[1].lower()
    content_type = (
        getattr(upload, 'content_type', None)
        or _content_type_from_extension(extension)
    )
    try:
        content = sanitize_document(read_limited_upload(upload), content_type)
    except ValueError as exc:
        raise ValidationError(str(exc)) from exc
    return SimpleUploadedFile(
        name=os.path.basename(upload.name),
        content=content,
        content_type=content_type,
    )
