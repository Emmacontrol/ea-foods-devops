# syntax=docker/dockerfile:1.7
ARG PYTHON_VERSION=3.13

# ---- Stage 1: build a virtualenv with only runtime dependencies ----
FROM python:${PYTHON_VERSION}-slim AS builder
ENV PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1
WORKDIR /build
COPY requirements.txt .
# - Install dependencies into an isolated virtualenv, then drop pip from it (build tool only).
# - Fetch the AWS RDS certificate bundle so the app can verify the database's TLS certificate.
RUN python -m venv /opt/venv \
 && /opt/venv/bin/pip install -r requirements.txt \
 && /opt/venv/bin/pip uninstall -y pip \
 && python -c "import urllib.request; urllib.request.urlretrieve('https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem', '/build/rds-global-bundle.pem')"

# ---- Stage 2: minimal runtime — no compilers, no pip, no build files ----
FROM python:${PYTHON_VERSION}-slim AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    WEB_CONCURRENCY=2

# Remove the base image's pip (and the libraries it vendors) — nothing installs at runtime.
# Fixed numeric UID/GID so orchestrators can verify the container is non-root.
RUN python -m pip uninstall -y pip \
 && groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app
COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/rds-global-bundle.pem /app/certs/rds-global-bundle.pem
# Code stays root-owned (read-only for the app user): a compromised process can't modify it.
COPY manage.py ./
COPY orders_api ./orders_api
COPY orders ./orders

USER 10001:10001
EXPOSE 8000

# Used by docker compose; ECS uses the ALB target group health check.
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

# --forwarded-allow-ips: trust X-Forwarded-* from the ALB (the only thing that can reach the task).
CMD ["gunicorn", "orders_api.wsgi:application", "--bind", "0.0.0.0:8000", "--access-logfile", "-", "--forwarded-allow-ips", "*"]
