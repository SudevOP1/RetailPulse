"""Shared pytest fixtures.

DB tests use the `engine` fixture, which skips the test cleanly when Postgres is
unreachable (so `pytest` stays green on a machine without the warehouse) but runs
it for real whenever the .env credentials work.
"""

from __future__ import annotations

import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts import db  # noqa: E402

RAW_DIR = ROOT / "data" / "raw"

# Verified row counts (PLAN.md §3a). Keyed by raw table name -> (csv file, rows).
RAW_TABLES: dict[str, tuple[str, int]] = {
    "orders": ("olist_orders_dataset.csv", 99_441),
    "customers": ("olist_customers_dataset.csv", 99_441),
    "order_items": ("olist_order_items_dataset.csv", 112_650),
    "order_payments": ("olist_order_payments_dataset.csv", 103_886),
    "order_reviews": ("olist_order_reviews_dataset.csv", 99_224),
    "products": ("olist_products_dataset.csv", 32_951),
    "sellers": ("olist_sellers_dataset.csv", 3_095),
    "geolocation": ("olist_geolocation_dataset.csv", 1_000_163),
    "product_category_name_translation": ("product_category_name_translation.csv", 71),
}


@pytest.fixture(scope="session")
def engine():
    if not db.is_reachable():
        url = db.db_url().render_as_string(hide_password=True)
        pytest.skip(f"Postgres unreachable at {url}")
    return db.get_engine()
