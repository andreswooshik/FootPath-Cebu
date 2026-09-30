"""Stable application errors for workflow conflicts."""

from config.application_errors import Conflict


class WorkflowConflict(Conflict):
    def __init__(self, code, message, **details):
        super().__init__({'code': code, 'message': message, **details})
