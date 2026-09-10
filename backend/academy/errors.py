"""Stable HTTP errors for domain workflow conflicts."""

from rest_framework import status
from rest_framework.exceptions import APIException


class WorkflowConflict(APIException):
    status_code = status.HTTP_409_CONFLICT
    default_code = 'conflict'

    def __init__(self, code, message, **details):
        super().__init__({'code': code, 'message': message, **details})
