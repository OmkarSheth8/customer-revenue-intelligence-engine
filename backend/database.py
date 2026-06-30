import os
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from sqlalchemy import create_engine, text

_BASE_DIR = Path(__file__).resolve().parent
load_dotenv(_BASE_DIR / ".env", override=True)

DATABASE_URL = os.getenv("DATABASE_URL")

if not DATABASE_URL:
    raise ValueError("DATABASE_URL is missing. Check your .env file.")

engine = create_engine(DATABASE_URL)


def fetch_all(query: str, params: dict[str, Any] | None = None):
    with engine.connect() as connection:
        result = connection.execute(text(query), params or {})
        rows = result.mappings().all()
        return [dict(row) for row in rows]


def fetch_one(query: str, params: dict[str, Any] | None = None):
    with engine.connect() as connection:
        result = connection.execute(text(query), params or {})
        row = result.mappings().first()
        return dict(row) if row else None