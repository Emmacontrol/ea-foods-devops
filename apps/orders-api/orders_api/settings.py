"""Minimal Django settings. All runtime config comes from environment variables
(12-factor), so the same image runs locally, in staging and in production."""

import os
from pathlib import Path

from django.core.exceptions import ImproperlyConfigured

BASE_DIR = Path(__file__).resolve().parent.parent

DEBUG = os.environ.get("DJANGO_DEBUG", "false").lower() == "true"

SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or ("dev-only-insecure-key" if DEBUG else None)
if not SECRET_KEY:
    raise ImproperlyConfigured("DJANGO_SECRET_KEY must be set when DJANGO_DEBUG is false")

# Public hostnames this app answers for (e.g. the ALB / custom domain).
# Health checks bypass this via HealthCheckMiddleware, so no "*" is needed.
ALLOWED_HOSTS = [h for h in os.environ.get("DJANGO_ALLOWED_HOSTS", "localhost,127.0.0.1").split(",") if h]

# Image tag, set by the deploy pipeline; returned by /health to confirm what is running.
APP_VERSION = os.environ.get("APP_VERSION", "dev")

INSTALLED_APPS = ["orders"]

MIDDLEWARE = [
    "orders.middleware.HealthCheckMiddleware",  # first: answers /health before host validation
    "django.middleware.security.SecurityMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "orders_api.urls"
WSGI_APPLICATION = "orders_api.wsgi.application"

# MySQL when DB_HOST is set (docker compose, ECS); SQLite otherwise (unit tests).
if os.environ.get("DB_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.mysql",
            "HOST": os.environ["DB_HOST"],
            "PORT": os.environ.get("DB_PORT", "3306"),
            "NAME": os.environ.get("DB_NAME", "orders"),
            "USER": os.environ.get("DB_USER", "orders"),
            "PASSWORD": os.environ.get("DB_PASSWORD", ""),
            "CONN_MAX_AGE": 60,
            "OPTIONS": {"charset": "utf8mb4"},
        }
    }
else:
    DATABASES = {"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": BASE_DIR / "db.sqlite3"}}

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
USE_TZ = True
TIME_ZONE = "UTC"

# Behind the ALB, TLS terminates at the load balancer; trust its forwarded-proto header.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Log to stdout only — the container runtime ships it to CloudWatch.
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {"format": '{"time":"%(asctime)s","level":"%(levelname)s","logger":"%(name)s","message":"%(message)s"}'}
    },
    "handlers": {"stdout": {"class": "logging.StreamHandler", "formatter": "json"}},
    "root": {"handlers": ["stdout"], "level": os.environ.get("LOG_LEVEL", "INFO")},
}
