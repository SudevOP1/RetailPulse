"""Export the analytics marts to exports/<model>.csv (Excel / Power BI fallback source).

The model list is read from dbt/retailpulse/models/marts/analytics/*.sql, so a new analytics
model is exported without editing this file.

    python scripts/export_marts.py
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from scripts.db import read_sql  # noqa: E402

ANALYTICS_DIR = ROOT / "dbt" / "retailpulse" / "models" / "marts" / "analytics"
EXPORT_DIR = ROOT / "exports"
SCHEMA = "marts"


def analytics_models() -> list[str]:
    return sorted(p.stem for p in ANALYTICS_DIR.glob("*.sql"))


def export_all(out_dir: Path = EXPORT_DIR) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    rows = {}
    for model in analytics_models():
        df = read_sql(f"select * from {SCHEMA}.{model}")
        df.to_csv(out_dir / f"{model}.csv", index=False, encoding="utf-8")
        rows[model] = len(df)
    return rows


if __name__ == "__main__":
    for model, n in export_all().items():
        print(f"{model:<20} {n:>7,} rows -> exports/{model}.csv")
