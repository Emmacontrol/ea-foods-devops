"""Settings for unit tests only: supplies a throwaway secret key, uses SQLite."""

import os

os.environ.setdefault("DJANGO_SECRET_KEY", "test-only-not-a-secret")
os.environ.pop("DB_HOST", None)

from .settings import *  # noqa: E402,F403
