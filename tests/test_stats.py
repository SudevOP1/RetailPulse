"""Phase 4: statistics helpers (no DB) + the resume bullet 2 numbers from marts.fact_orders (DB).

PLAN.md §8 Phase 4 expected ~784 per arm for 0.54 vs 0.49. That figure is half the correct
value: NormalIndPower's nobs1 is the per-arm size, and the textbook pooled-variance formula
agrees at ~1,567 (Cohen 1988, Table 6.4.1: h = 0.20 needs 392 per group, i.e. 2 * (z_a + z_b)^2 / h^2).
"""

from __future__ import annotations

import math

import numpy as np
import pandas as pd
import pytest
from scipy.stats import norm
from sqlalchemy import text

from scripts import stats_helpers as sh

PP = 0.01


def _classic_n(p1: float, p2: float, alpha: float = 0.05, power: float = 0.8) -> float:
    """Pooled/unpooled normal-approximation sample size per arm (Fleiss, no continuity correction)."""
    za, zb = norm.ppf(1 - alpha / 2), norm.ppf(power)
    pbar = (p1 + p2) / 2
    num = za * math.sqrt(2 * pbar * (1 - pbar)) + zb * math.sqrt(p1 * (1 - p1) + p2 * (1 - p2))
    return (num / (p1 - p2)) ** 2


# --- power analysis -------------------------------------------------------------------


def test_power_054_vs_049_per_arm():
    n = sh.n_per_arm(0.54, 0.49)
    assert n == pytest.approx(1567, abs=5)
    assert n == pytest.approx(_classic_n(0.54, 0.49), rel=0.01)


def test_power_matches_cohen_table():
    # Cohen's h = 0.2 at alpha .05 two-sided, power .8 -> 392 per group.
    p2 = math.sin((2 * math.asin(math.sqrt(0.5)) - 0.2) / 2) ** 2
    assert sh.n_per_arm(0.5, p2) == pytest.approx(393, abs=1)


def test_power_symmetric_and_monotone():
    assert sh.n_per_arm(0.54, 0.49) == sh.n_per_arm(0.49, 0.54)
    assert sh.n_per_arm(0.54, 0.46) < sh.n_per_arm(0.54, 0.49)
    assert sh.n_per_arm(0.54, 0.49, power=0.9) > sh.n_per_arm(0.54, 0.49)


def test_mde_table_duration():
    t = sh.mde_table(0.54, [5, 8], units_per_month=510)
    assert list(t["mde_pp"]) == [5, 8]
    assert t["p_treatment"].tolist() == pytest.approx([0.49, 0.46])
    assert (t["n_total"] == 2 * t["n_per_arm"]).all()
    assert t.loc[0, "months"] == pytest.approx(2 * sh.n_per_arm(0.54, 0.49) / 510)
    assert t["months"].is_monotonic_decreasing


# --- A/A simulation and SRM -----------------------------------------------------------


def test_aa_false_positive_rate_near_alpha():
    pvals = sh.simulate_aa(0.54, 1567, n_sims=4_000, seed=1)
    assert len(pvals) == 4_000
    assert (pvals < 0.05).mean() == pytest.approx(0.05, abs=0.012)


def test_aa_reproducible():
    first = sh.simulate_aa(0.3, 500, n_sims=50, seed=7)
    assert np.array_equal(first, sh.simulate_aa(0.3, 500, n_sims=50, seed=7))


def test_srm_pvalue():
    assert sh.srm_pvalue(5000, 5000) == pytest.approx(1.0)
    assert sh.srm_pvalue(5000, 5300) < 0.01


# --- descriptive helpers --------------------------------------------------------------


def test_days_late_bucket_edges():
    days = pd.Series([-30, -7, -6, 0, 1, 3, 4, 7, 8, 14, 15, 100])
    got = sh.days_late_bucket(days).astype(str).tolist()
    assert got == ["<=-7", "<=-7", "-6..0", "-6..0", "1-3", "1-3", "4-7", "4-7", "8-14", "8-14", "15+", "15+"]
    assert list(sh.days_late_bucket(days).cat.categories) == sh.DAYS_LATE_LABELS


def test_top_n_or_other():
    s = pd.Series(["a", "a", "a", "b", "b", "c", None])
    assert sh.top_n_or_other(s, 2).tolist() == ["a", "a", "a", "b", "b", "other", "other"]


def test_two_proportion_summary():
    r = sh.two_proportion_summary(100, 200, 10, 200)
    assert r["risk_ratio"] == pytest.approx(10.0)
    assert r["odds_ratio"] == pytest.approx(19.0)
    assert r["rr_ci_low"] < 10 < r["rr_ci_high"]
    assert r["diff_ci_low"] < 0.45 < r["diff_ci_high"]
    assert r["p_value"] < 1e-10


# --- resume bullet 2 numbers (DB) -----------------------------------------------------

LATE_SQL = """
select
    avg(is_late::int)                                                         as late_share,
    count(*)                                                                  as delivered_dated,
    avg(is_one_star::int) filter (where is_late and review_score is not null)     as one_star_late,
    avg(is_one_star::int) filter (where not is_late and review_score is not null) as one_star_on_time
from marts.fact_orders
where is_late is not null
"""


@pytest.fixture(scope="module")
def late_numbers(engine):
    with engine.connect() as conn:
        return {k: float(v) for k, v in conn.execute(text(LATE_SQL)).mappings().one().items()}


def test_late_share(late_numbers):
    assert late_numbers["delivered_dated"] == 96_470
    assert late_numbers["late_share"] == pytest.approx(0.0677, abs=PP)


def test_one_star_rates_and_ratio(late_numbers):
    late, on_time = late_numbers["one_star_late"], late_numbers["one_star_on_time"]
    assert late == pytest.approx(0.538, abs=PP)
    assert on_time == pytest.approx(0.066, abs=PP)
    assert late / on_time == pytest.approx(8.1, abs=0.5)
