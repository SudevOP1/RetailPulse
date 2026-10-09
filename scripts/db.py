"""Shared SQLAlchemy engine built from .env (PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD).

Used by notebooks, tests and export scripts so credentials live in exactly one place.

    from scripts.db import get_engine, read_sql
    df = read_sql("select count(*) from raw.orders")
"""

from __future__ import annotations

import os
from functools import lru_cache
from pathlib import Path

import pandas as pd
from dotenv import load_dotenv
from sqlalchemy import URL, Engine, create_engine, text

ROOT = Path(__file__).resolve().parents[1]
load_dotenv(ROOT / ".env")


def db_url() -> URL:
    return URL.create(
        "postgresql+psycopg",
        username=os.getenv("PGUSER", "rp_user"),
        password=os.getenv("PGPASSWORD"),
        host=os.getenv("PGHOST", "localhost"),
        port=int(os.getenv("PGPORT", "5432")),
        database=os.getenv("PGDATABASE", "retailpulse"),
    )


@lru_cache(maxsize=1)
def get_engine() -> Engine:
    return create_engine(db_url(), pool_pre_ping=True, connect_args={"connect_timeout": 5})


def is_reachable() -> bool:
    """True if Postgres accepts a connection with the .env credentials."""
    try:
        with get_engine().connect() as conn:
            conn.execute(text("select 1"))
    except Exception:
        return False
    return True


def read_sql(sql: str, **params) -> pd.DataFrame:
    with get_engine().connect() as conn:
        return pd.read_sql(text(sql), conn, params=params or None)


if __name__ == "__main__":
    url = db_url()
    print(f"Connecting to {url.render_as_string(hide_password=True)} ...")
    print("OK" if is_reachable() else "UNREACHABLE")
