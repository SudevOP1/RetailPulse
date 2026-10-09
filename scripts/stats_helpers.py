"""Reusable statistics helpers for the Phase 4 notebooks (late delivery + A/B sizing).

Kept out of the notebooks so tests/test_stats.py can check them without a database.

    from scripts.stats_helpers import days_late_bucket, two_proportion_summary, n_per_arm
"""

from __future__ import annotations

import math

import numpy as np
import pandas as pd
from scipy.stats import chisquare, norm
from statsmodels.stats.power import NormalIndPower
from statsmodels.stats.proportion import (
    confint_proportions_2indep,
    proportion_effectsize,
    proportions_ztest,
)

# Days-late buckets (PLAN §8 Phase 4): days_late = delivered::date - estimated::date.
# Negative = arrived before the promised date.
DAYS_LATE_EDGES = [-math.inf, -7, 0, 3, 7, 14, math.inf]
DAYS_LATE_LABELS = ["<=-7", "-6..0", "1-3", "4-7", "8-14", "15+"]


def days_late_bucket(days_late: pd.Series) -> pd.Series:
    """Ordered categorical bucket for integer days_late (right-closed bins)."""
    return pd.cut(days_late, bins=DAYS_LATE_EDGES, labels=DAYS_LATE_LABELS, right=True)


def top_n_or_other(values: pd.Series, n: int, other: str = "other") -> pd.Series:
    """Keep the n most frequent values, replace the rest (and nulls) with `other`."""
    keep = values.value_counts().nlargest(n).index
    return values.where(values.isin(keep), other).fillna(other)


def two_proportion_summary(x1: int, n1: int, x2: int, n2: int, alpha: float = 0.05) -> dict[str, float]:
    """Compare p1 = x1/n1 (treated, e.g. late) with p2 = x2/n2 (reference, e.g. on time).

    Returns the two-sided z-test, the difference p1 - p2 with a Newcombe (Wilson) CI,
    and the risk ratio and odds ratio, each with a log-scale Wald CI.
    """
    p1, p2 = x1 / n1, x2 / n2
    z, p_value = proportions_ztest([x1, x2], [n1, n2], alternative="two-sided")
    diff_lo, diff_hi = confint_proportions_2indep(
        x1, n1, x2, n2, method="newcomb", compare="diff", alpha=alpha
    )
    zcrit = _z_crit(alpha)

    rr = p1 / p2
    se_log_rr = math.sqrt(1 / x1 - 1 / n1 + 1 / x2 - 1 / n2)
    a, b, c, d = x1, n1 - x1, x2, n2 - x2
    odds_ratio = (a * d) / (b * c)
    se_log_or = math.sqrt(1 / a + 1 / b + 1 / c + 1 / d)
    return {
        "p1": p1,
        "p2": p2,
        "diff": p1 - p2,
        "diff_ci_low": float(diff_lo),
        "diff_ci_high": float(diff_hi),
        "z": float(z),
        "p_value": float(p_value),
        "risk_ratio": rr,
        "rr_ci_low": math.exp(math.log(rr) - zcrit * se_log_rr),
        "rr_ci_high": math.exp(math.log(rr) + zcrit * se_log_rr),
        "odds_ratio": odds_ratio,
        "or_ci_low": math.exp(math.log(odds_ratio) - zcrit * se_log_or),
        "or_ci_high": math.exp(math.log(odds_ratio) + zcrit * se_log_or),
    }


def n_per_arm(p_control: float, p_treatment: float, alpha: float = 0.05, power: float = 0.8) -> int:
    """Units per arm for a two-sided two-proportion test (Cohen's h, normal approximation)."""
    h = proportion_effectsize(p_control, p_treatment)
    n = NormalIndPower().solve_power(effect_size=abs(h), alpha=alpha, power=power, ratio=1.0)
    return math.ceil(n)


def mde_table(
    p_control: float,
    mdes_pp: list[float],
    units_per_month: float,
    alpha: float = 0.05,
    power: float = 0.8,
    arms: int = 2,
) -> pd.DataFrame:
    """Sample size and duration for each minimum detectable effect (absolute pp reduction).

    `units_per_month` is the eligible traffic (e.g. late orders per month) split across `arms`.
    """
    rows = []
    for mde in mdes_pp:
        p_t = p_control - mde / 100
        n = n_per_arm(p_control, p_t, alpha=alpha, power=power)
        rows.append(
            {
                "mde_pp": mde,
                "p_control": p_control,
                "p_treatment": round(p_t, 4),
                "relative_mde": mde / 100 / p_control,
                "n_per_arm": n,
                "n_total": n * arms,
                "months": n * arms / units_per_month,
            }
        )
    return pd.DataFrame(rows)


def simulate_aa(
    p: float, n_per_arm: int, n_sims: int = 1_000, alpha: float = 0.05, seed: int = 42
) -> np.ndarray:
    """p-values of `n_sims` A/A experiments (both arms share true rate p), two-proportion z-test.

    Under the null the p-values are ~Uniform(0, 1), so mean(p < alpha) should be ~alpha.
    """
    rng = np.random.default_rng(seed)
    a = rng.binomial(n_per_arm, p, size=n_sims)
    b = rng.binomial(n_per_arm, p, size=n_sims)
    pooled = (a + b) / (2 * n_per_arm)
    se = np.sqrt(pooled * (1 - pooled) * 2 / n_per_arm)
    z = np.divide(a - b, n_per_arm * se, out=np.zeros(n_sims), where=se > 0)
    return 2 * norm.sf(np.abs(z))


def srm_pvalue(n_a: int, n_b: int, expected_share_a: float = 0.5) -> float:
    """Chi-square goodness-of-fit p-value for sample-ratio mismatch between two arms."""
    total = n_a + n_b
    expected = [total * expected_share_a, total * (1 - expected_share_a)]
    return float(chisquare([n_a, n_b], f_exp=expected).pvalue)


def _z_crit(alpha: float) -> float:
    return float(norm.ppf(1 - alpha / 2))
