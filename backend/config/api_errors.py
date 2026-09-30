"""Translate application failures at the REST boundary."""

from rest_framework.exceptions import APIException, ValidationError
from rest_framework.views import exception_handler as drf_exception_handler

from .application_errors import ApplicationError


def exception_handler(exc, context):
    if isinstance(exc, ApplicationError):
        if exc.kind == 'invalid':
            exc = ValidationError(exc.detail)
        else:
            translated = APIException(exc.detail)
            translated.status_code = {'forbidden': 403, 'missing': 404, 'conflict': 409}[exc.kind]
            exc = translated
    return drf_exception_handler(exc, context)
