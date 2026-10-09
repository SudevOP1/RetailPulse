"""Phase 3: analytics marts reproduce the PLAN.md §3a sanity values within tolerance.

Tolerances (PLAN §8 Phase 3): ±1 pp for rates, ±1 for the Pareto count, ±2% for GMV.
"""

from __future__ import annotations

from decimal import Decimal

import pytest
from sqlalchemy import text

from tests.conftest import ROOT

ANALYTICS_DIR = ROOT / "dbt" / "retailpulse" / "models" / "marts" / "analytics"
ANALYTICS_MODELS = [
    "kpi_monthly",
    "kpi_summary",
    "cohort_retention",
    "rfm_segments",
    "category_pareto",
    "seller_scorecard",
    "freight_by_state",
]
PP = 0.01  # one percentage point


def _num(value):
    """Postgres numeric comes back as Decimal; pytest.approx needs float."""
    return float(value) if isinstance(value, Decimal) else value


def _row(engine, sql: str) -> dict:
    with engine.connect() as conn:
        return {k: _num(v) for k, v in conn.execute(text(sql)).mappings().one().items()}


def _scalar(engine, sql: str):
    with engine.connect() as conn:
        return _num(conn.execute(text(sql)).scalar_one())


# --- static checks (no database) -------------------------------------------------------


def test_all_analytics_models_present():
    assert sorted(p.stem for p in ANALYTICS_DIR.glob("*.sql")) == sorted(ANALYTICS_MODELS)


def test_analytics_sql_uses_window_functions():
    """Resume bullet 3 claims CTEs + window functions; each named technique appears somewhere."""
    body = " ".join(p.read_text(encoding="utf-8").lower() for p in ANALYTICS_DIR.glob("*.sql"))
    for fn in ("lag(", "ntile(", "percent_rank(", "first_value(", "rank(", "over (partition by", "with "):
        assert fn in body, fn


# --- database checks -------------------------------------------------------------------


@pytest.mark.parametrize("model", ANALYTICS_MODELS)
def test_analytics_model_not_empty(engine, model):
    assert _scalar(engine, f"select count(*) from marts.{model}") > 0


def test_repeat_purchase_rate(engine):
    """§3a: 3.0% (2,801 / 93,350). Denominator here is 93,358: 8 delivered orders lack a date."""
    s = _row(engine, "select * from marts.kpi_summary")
    assert s["repeat_customers"] == 2_801
    assert s["customers"] == 93_358
    assert s["repeat_purchase_rate"] == pytest.approx(0.030, abs=PP)


def test_gmv_and_aov(engine):
    s = _row(engine, "select gmv, aov, freight_share, late_share from marts.kpi_summary")
    assert float(s["gmv"]) == pytest.approx(13.2e6, rel=0.02)
    assert float(s["aov"]) == pytest.approx(137, rel=0.02)
    assert float(s["freight_share"]) == pytest.approx(0.142, abs=PP)
    assert float(s["late_share"]) == pytest.approx(0.0677, abs=PP)


def test_category_pareto_17_of_73(engine):
    n = _scalar(engine, "select count(*) from marts.category_pareto")
    a = _scalar(engine, "select count(*) from marts.category_pareto where abc_class = 'A'")
    via_cum_share = _scalar(engine, "select count(*) + 1 from marts.category_pareto where cum_share <= 0.8")
    assert n == 73
    assert a == via_cum_share
    assert abs(a - 17) <= 1


def test_pareto_cum_share_ends_at_one(engine):
    assert float(_scalar(engine, "select max(cum_share) from marts.category_pareto")) == pytest.approx(1.0)


def test_kpi_monthly_trend_window(engine):
    r = _row(engine, "select count(*) n, min(year_month) lo, max(year_month) hi from marts.kpi_monthly")
    assert (r["n"], r["lo"], r["hi"]) == (20, "2017-01", "2018-08")


def test_yoy_order_growth_jan_aug(engine):
    """§3a: 22,968 (2017) -> 53,991 (2018) orders, Jan-Aug."""
    sql = "select sum(orders) from marts.kpi_monthly where month_start between '{y}-01-01' and '{y}-08-01'"
    assert _scalar(engine, sql.format(y="2017")) == 22_968
    assert _scalar(engine, sql.format(y="2018")) == 53_991


def test_month1_cohort_retention(engine):
    """§3a: average month-1 retention ≈ 0.46% over cohorts with >= 500 customers."""
    m1 = _scalar(
        engine,
        "select avg(retention_pct) from marts.cohort_retention where month_index = 1 and cohort_size >= 500",
    )
    assert float(m1) == pytest.approx(0.46, abs=0.1)


def test_cohort_sizes_cover_every_active_customer(engine):
    sized = _scalar(engine, "select sum(cohort_size) from marts.cohort_retention where month_index = 0")
    active = _scalar(
        engine,
        "select count(distinct customer_key) from marts.fact_orders "
        "where order_status not in ('canceled', 'unavailable')",
    )
    assert sized == active


def test_rfm_one_row_per_delivered_customer(engine):
    assert _scalar(engine, "select count(*) from marts.rfm_segments") == 93_358
    repeat = _scalar(engine, "select count(*) from marts.rfm_segments where f_flag")
    assert repeat == 2_801


def test_freight_and_late_by_state(engine):
    with engine.connect() as conn:
        sql = "select customer_state, freight_share, late_rate from marts.freight_by_state"
        result = conn.execute(text(sql))
        rows = {r["customer_state"]: r for r in result.mappings()}
    assert len(rows) == 27
    assert float(rows["SP"]["freight_share"]) == pytest.approx(0.122, abs=PP)
    assert float(rows["RR"]["freight_share"]) == pytest.approx(0.222, abs=PP)
    assert float(rows["SP"]["late_rate"]) == pytest.approx(0.045, abs=PP)
    assert float(rows["AL"]["late_rate"]) == pytest.approx(0.214, abs=PP)
    assert float(rows["MA"]["late_rate"]) == pytest.approx(0.174, abs=PP)


def test_worst_late_decile_sellers(engine):
    """§3a: worst decile ≈ 82 sellers, 5.3% of seller-orders, 13.3% of late seller-orders."""
    worst = _row(
        engine,
        "select count(*) n, sum(orders) so, sum(late_orders) lo"
        " from marts.seller_scorecard where late_decile = 10",
    )
    total = _row(
        engine,
        "select count(*) so, count(*) filter (where is_late) lo from ("
        " select seller_key, order_id, bool_or(is_late) is_late from marts.fact_order_items"
        " where is_delivered group by 1, 2) s",
    )
    assert abs(worst["n"] - 82) <= 5
    assert worst["so"] / total["so"] == pytest.approx(0.053, abs=PP)
    assert worst["lo"] / total["lo"] == pytest.approx(0.133, abs=PP)
