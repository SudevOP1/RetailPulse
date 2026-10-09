"""Phase 1: the 9 raw tables (and the CSVs they come from) match PLAN.md §3a row counts."""

from __future__ import annotations

import csv
import re

import pandas as pd
import pytest
from sqlalchemy import text

from tests.conftest import RAW_DIR, RAW_TABLES, ROOT

SCHEMA_SQL = ROOT / "scripts" / "00_create_raw_schema.sql"


def _schema_definitions() -> dict[str, list[tuple[str, str]]]:
    """Parse `create table raw.<t> (...)` blocks from the raw schema DDL into (column, type) pairs."""
    sql = SCHEMA_SQL.read_text(encoding="utf-8")
    tables = {}
    for name, body in re.findall(r"create table raw\.(\w+) \((.*?)\n\);", sql, flags=re.S):
        lines = [line.split("--")[0].strip().rstrip(",") for line in body.splitlines()]
        tables[name] = [tuple(line.split()[:2]) for line in lines if line]
    return tables


def _schema_columns() -> dict[str, list[str]]:
    return {t: [col for col, _ in defs] for t, defs in _schema_definitions().items()}


def test_schema_declares_all_tables_as_text():
    defs = _schema_definitions()
    assert set(defs) == set(RAW_TABLES)
    assert {typ for cols in defs.values() for _, typ in cols} == {"text"}


@pytest.mark.parametrize("table", RAW_TABLES)
def test_schema_matches_csv_header(table):
    path = RAW_DIR / RAW_TABLES[table][0]
    if not path.exists():
        pytest.skip(f"{path.name} not downloaded (python scripts/download_data.py)")
    with path.open(encoding="utf-8-sig", newline="") as fh:
        header = next(csv.reader(fh))
    assert _schema_columns()[table] == header


@pytest.mark.parametrize("table", RAW_TABLES)
def test_csv_row_counts(table):
    file, expected = RAW_TABLES[table]
    path = RAW_DIR / file
    if not path.exists():
        pytest.skip(f"{file} not downloaded (python scripts/download_data.py)")
    # Proper CSV parsing: reviews have newlines inside quoted fields, so line counts lie.
    assert len(pd.read_csv(path, dtype=str, usecols=[0])) == expected


@pytest.mark.db
@pytest.mark.parametrize("table", RAW_TABLES)
def test_raw_table_row_counts(engine, table):
    with engine.connect() as conn:
        n = conn.execute(text(f"select count(*) from raw.{table}")).scalar_one()
    assert n == RAW_TABLES[table][1]


@pytest.mark.db
def test_raw_columns_are_all_text(engine):
    q = text(
        "select table_name, column_name, data_type from information_schema.columns "
        "where table_schema = 'raw' order by table_name, ordinal_position"
    )
    with engine.connect() as conn:
        rows = conn.execute(q).all()
    assert {r.table_name for r in rows} == set(RAW_TABLES)
    assert {r.data_type for r in rows} == {"text"}
