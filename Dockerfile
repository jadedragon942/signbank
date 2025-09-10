# Minimal, flexible Dockerfile for running a Signbank (Django) instance
# Defaults to cloning the Global-signbank repo, but can be pointed at any fork
# via build args.

FROM python:3.11-slim AS base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# System packages commonly required by Signbank deployments
# - git: clone repository
# - build-essential, libpq-dev: build wheels and PostgreSQL client libs
# - libjpeg-dev, zlib1g-dev: Pillow image support
# - libmagic-dev: filetype detection (python-magic)
# - gettext: msgfmt for i18n
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       git \
       build-essential \
       libpq-dev \
       libjpeg-dev \
       zlib1g-dev \
       libmagic-dev \
       gettext \
    && rm -rf /var/lib/apt/lists/*

# Where the app will live in the image
WORKDIR /app

# Allow overriding which Signbank repo/ref to build
ARG REPO_URL=https://github.com/Signbank/Global-signbank.git
ARG REPO_REF=master

# Clone the requested Signbank repository
RUN git clone --depth 1 --branch ${REPO_REF} ${REPO_URL} /app

# Install Python dependencies. Try common locations used across forks.
# Also install gunicorn for production serving if not already specified.
RUN set -eux; \
    if [ -f requirements.txt ]; then \
        pip install --no-cache-dir -r requirements.txt; \
    elif [ -f requirements/base.txt ]; then \
        pip install --no-cache-dir -r requirements/base.txt; \
    elif [ -f pip_requirements.txt ]; then \
        pip install --no-cache-dir -r pip_requirements.txt; \
    else \
        echo "No known requirements file found; proceeding"; \
    fi; \
    pip install --no-cache-dir gunicorn

# Environment defaults (override at runtime as needed)
# Ensure this matches the Django settings module in your chosen repo
ENV DJANGO_SETTINGS_MODULE=signbank.settings \
    PORT=8000 \
    APP_DIR=

# Expose the Django/Gunicorn port
EXPOSE 8000

# By default, run migrations and start Gunicorn. Override this CMD in compose/k8s
# if you need a different entrypoint. Database must be reachable at runtime.
CMD sh -c "\
	python /app/bin/develop.py collectstatic --noinput || true; \
	python /app/bin/develop.py migrate --noinput || true; \
    exec gunicorn django.core.wsgi:get_wsgi_application --bind 127.0.0.1:${PORT} --workers 3"
