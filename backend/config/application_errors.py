"""Transport-independent failures raised by application workflows."""


class ApplicationError(Exception):
    kind = 'invalid'
    default_detail = 'Invalid operation.'

    def __init__(self, detail=None):
        self.detail = self.default_detail if detail is None else detail
        super().__init__(str(self.detail))


class InvalidOperation(ApplicationError):
    pass


class ForbiddenOperation(ApplicationError):
    kind = 'forbidden'


class MissingResource(ApplicationError):
    kind = 'missing'
    default_detail = 'Not found.'


class Conflict(ApplicationError):
    kind = 'conflict'
