"""Phase 2: core star schema row counts, grains and the duplicate-review flag (PLAN.md §8 Phase 2)."""

from __future__ import annotations

import re

import pytest
from sqlalchemy import text

from tests.conftest import ROOT

DBT_DIR = ROOT / "dbt" / "retailpulse"
CORE_DIR = DBT_DIR / "models" / "marts" / "core"

# Expected rows per core mart (PLAN.md §3a / §8 Phase 2).
CORE_COUNTS = {
    "fact_orders": 99_441,
    "fact_order_items": 112_650,
    "dim_customer": 96_096,
    "dim_seller": 3_095,
    "dim_product": 32_951,
    "dim_date": 852,  # 2016-09-01 .. 2018-12-31
}

# Grain (primary key columns) of every core mart and order-level intermediate model.
GRAINS = {
    "marts.fact_orders": ["order_id"],
    "marts.fact_order_items": ["order_id", "order_item_id"],
    "marts.dim_customer": ["customer_key"],
    "marts.dim_seller": ["seller_key"],
    "marts.dim_product": ["product_key"],
    "marts.dim_date": ["date_key"],
    "intermediate.int_order_reviews_latest": ["order_id"],
    "intermediate.int_order_items_agg": ["order_id"],
    "intermediate.int_order_payments_agg": ["order_id"],
}


def _scalar(engine, sql: str):
    with engine.connect() as conn:
        return conn.execute(text(sql)).scalar_one()


# --- static checks (no database) -------------------------------------------------------


def test_star_schema_has_two_facts_and_four_dims():
    models = sorted(p.stem for p in CORE_DIR.glob("*.sql"))
    assert [m for m in models if m.startswith("fact_")] == ["fact_order_items", "fact_orders"]
    assert len([m for m in models if m.startswith("dim_")]) == 4


def test_at_least_25_dbt_tests_declared():
    """Rough static count: generic tests in yml + singular tests. dbt build reports the exact number."""
    yml_tests = 0
    for path in DBT_DIR.joinpath("models").rglob("*.yml"):
        body = path.read_text(encoding="utf-8")
        yml_tests += len(
            re.findall(r"^\s*- (unique|not_null|accepted_values|relationships|dbt_utils\.\w+)\b", body, re.M)
        )
        yml_tests += sum(len(m.split(",")) for m in re.findall(r"data_tests: \[(.*?)\]", body))
    singular = len(list(DBT_DIR.joinpath("tests").glob("*.sql")))
    assert yml_tests + singular >= 25


# --- database checks -------------------------------------------------------------------


@pytest.mark.parametrize("table", CORE_COUNTS)
def test_core_row_counts(engine, table):
    assert _scalar(engine, f"select count(*) from marts.{table}") == CORE_COUNTS[table]


@pytest.mark.parametrize("relation", GRAINS)
def test_grain_is_unique(engine, relation):
    cols = ", ".join(GRAINS[relation])
    dupes = _scalar(
        engine, f"select count(*) from (select {cols} from {relation} group by {cols} having count(*) > 1) d"
    )
    assert dupes == 0


def test_one_latest_review_per_reviewed_order(engine):
    reviewed_orders = _scalar(engine, "select count(distinct order_id) from staging.stg_olist__reviews")
    latest = _scalar(engine, "select count(*) from intermediate.int_order_reviews_latest")
    assert latest == reviewed_orders == 98_673


def test_duplicate_review_test_stored_failures(engine):
    """Test #15 warns: 789 duplicated review_id values, i.e. 814 extra rows (PLAN §3a)."""
    assert _scalar(engine, "select count(*) from dbt_test__audit.dup_review_ids") == 789
    assert _scalar(engine, "select sum(n_records) - count(*) from dbt_test__audit.dup_review_ids") == 814


def test_every_category_translated(engine):
    assert _scalar(engine, "select count(*) from marts.dim_product where category_en is null") == 0
    assert _scalar(engine, "select count(*) from marts.dim_product where category_en = 'unknown'") == 610


def test_late_share_matches_definition(engine):
    """Sanity: late share of delivered orders with a delivered date = 6,534 / 96,470 (PLAN §3a)."""
    late, denom = (
        _scalar(engine, "select count(*) filter (where is_late) from marts.fact_orders"),
        _scalar(engine, "select count(is_late) from marts.fact_orders"),
    )
    assert (late, denom) == (6_534, 96_470)


def test_fact_items_reconcile_to_fact_orders(engine):
    item_gmv = _scalar(engine, "select sum(price) from marts.fact_order_items")
    order_gmv = _scalar(engine, "select sum(items_value) from marts.fact_orders")
    assert item_gmv == order_gmv
