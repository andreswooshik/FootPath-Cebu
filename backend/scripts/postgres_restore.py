"""Restore a pg_dump archive after an explicit database-name confirmation."""
from __future__ import annotations

import argparse
import os
from pathlib import Path
import shutil
import subprocess


def required(name: str) -> str:
    value = os.environ.get(name, '').strip()
    if not value:
        raise SystemExit(f'{name} is required.')
    return value


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('archive')
    parser.add_argument(
        '--confirm-database',
        required=True,
        help='Must exactly equal DB_NAME; restore replaces existing objects.',
    )
    args = parser.parse_args()
    database = required('DB_NAME')
    if args.confirm_database != database:
        raise SystemExit('--confirm-database must exactly match DB_NAME.')
    archive = Path(args.archive).resolve()
    if not archive.is_file() or archive.suffix != '.dump':
        raise SystemExit('Archive must be an existing .dump file.')
    if shutil.which('pg_restore') is None:
        raise SystemExit('pg_restore is not installed or not on PATH.')

    env = os.environ.copy()
    env['PGPASSWORD'] = required('DB_PASSWORD')
    env['PGSSLMODE'] = os.environ.get('DB_SSLMODE', 'require')
    command = [
        'pg_restore', '--clean', '--if-exists', '--no-owner', '--no-acl',
        '--exit-on-error',
        '--host', required('DB_HOST'),
        '--port', os.environ.get('DB_PORT', '5432'),
        '--username', required('DB_USER'),
        '--dbname', database,
        str(archive),
    ]
    subprocess.run(command, env=env, check=True)


if __name__ == '__main__':
    main()
