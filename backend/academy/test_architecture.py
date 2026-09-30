"""Guard the application services' transport boundary and public error mapping."""

import ast
from pathlib import Path

from django.test import SimpleTestCase

from config.api_errors import exception_handler
from config.application_errors import (
    Conflict,
    ForbiddenOperation,
    InvalidOperation,
    MissingResource,
)


class ApplicationBoundaryTests(SimpleTestCase):
    def test_extracted_services_do_not_import_http_adapters(self):
        root = Path(__file__).resolve().parent.parent
        for name in (
            'academy/attendance_service.py',
            'academy/dispute_service.py',
            'academy/eligibility_service.py',
            'academy/injury_service.py',
            'academy/tournament_publication.py',
            'academy/errors.py',
            'accounts/registration_service.py',
            'config/application_errors.py',
        ):
            with self.subTest(module=name):
                tree = ast.parse((root / name).read_text(encoding='utf-8'))
                imports = []
                for node in ast.walk(tree):
                    if isinstance(node, ast.ImportFrom):
                        imports.append(node.module or '')
                    elif isinstance(node, ast.Import):
                        imports.extend(alias.name for alias in node.names)
                self.assertFalse(
                    [
                        module
                        for module in imports
                        if module.startswith(('rest_framework', 'django.http', 'django.shortcuts'))
                        or any(part.startswith('view') for part in module.split('.'))
                    ]
                )

    def test_api_preserves_application_error_status_and_detail(self):
        for error, expected in (
            (InvalidOperation({'field': 'Invalid value'}), 400),
            (ForbiddenOperation('Forbidden'), 403),
            (MissingResource(), 404),
            (Conflict({'code': 'CONFLICT', 'message': 'Retry'}), 409),
        ):
            with self.subTest(error=type(error).__name__):
                response = exception_handler(error, {})
                self.assertEqual(response.status_code, expected)
                self.assertIsNotNone(response.data)
        response = exception_handler(Conflict({'code': 'CONFLICT'}), {})
        self.assertEqual(response.data['code'], 'CONFLICT')
        self.assertIsNone(exception_handler(RuntimeError('unexpected'), {}))
