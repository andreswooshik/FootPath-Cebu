"""Create and rotate a PostgreSQL custom-format backup using pg_dump.

Credentials come from the same DB_* environment variables as Django. The
password is passed only through the child process environment and is never
printed or placed on the command line.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
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
    parser.add_argument('--output-dir', default='backups')
    parser.add_argument('--retain', type=int, default=14)
    args = parser.parse_args()
    if args.retain < 1:
        raise SystemExit('--retain must be at least 1.')
    if shutil.which('pg_dump') is None:
        raise SystemExit('pg_dump is not installed or not on PATH.')

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    database = required('DB_NAME')
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    destination = output_dir / f'{database}-{stamp}.dump'
    env = os.environ.copy()
    env['PGPASSWORD'] = required('DB_PASSWORD')
    env['PGSSLMODE'] = os.environ.get('DB_SSLMODE', 'require')
    command = [
        'pg_dump', '--format=custom', '--no-owner', '--no-acl',
        '--host', required('DB_HOST'),
        '--port', os.environ.get('DB_PORT', '5432'),
        '--username', required('DB_USER'),
        '--file', str(destination),
        database,
    ]
    subprocess.run(command, env=env, check=True)

    backups = sorted(output_dir.glob(f'{database}-*.dump'), reverse=True)
    for stale in backups[args.retain:]:
        stale.unlink()
    print(destination)


if __name__ == '__main__':
    main()
