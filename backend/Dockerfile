FROM python:3.14-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

WORKDIR /app

COPY requirements.txt ./
RUN python -m pip install --upgrade pip && \
    python -m pip install -r requirements.txt

COPY . ./

RUN DJANGO_SECRET_KEY=container-build-only-secret-0123456789-abcdefghijklmnopqrstuvwxyz \
    DJANGO_DEBUG=1 \
    python manage.py collectstatic --noinput

# Keep the application and mounted credentials outside a root-owned process.
# UID/GID 10001 is explicit so Linux deployment hosts can grant read access to
# bind-mounted secret files without guessing an image-assigned system ID.
RUN groupadd --gid 10001 app && \
    useradd --uid 10001 --gid app --no-create-home \
    --shell /usr/sbin/nologin app && \
    mkdir -p /app/media && \
    chown -R app:app /app

USER app

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD python -c "import urllib.request; r=urllib.request.Request('http://127.0.0.1:8000/api/ready/', headers={'X-Forwarded-Proto':'https'}); raise SystemExit(0 if urllib.request.urlopen(r, timeout=4).status == 200 else 1)"

CMD ["gunicorn", "config.wsgi:application", "--bind", "0.0.0.0:8000", "--workers", "3", "--timeout", "60", "--access-logfile", "-", "--error-logfile", "-"]
