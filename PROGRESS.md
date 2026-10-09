# RetailPulse: progress log

Append one entry per completed phase (newest at the bottom). Status of record lives in PLAN.md §0.

## Entry template

```
## Phase N: <name> (YYYY-MM-DD)

**Shipped:** <files/models/notebooks>
**Key numbers:** <metric = value (PLAN §3a value)>, …
**Tests:** ruff <ok>; pytest <x passed / y skipped>; dbt build <PASS=… WARN=… ERROR=…>; notebooks <executed>
**Deferred:** <item, reason>
**Decisions:** <definitions or trade-offs made, also logged in docs/data_quality_log.md or docs/kpi_definitions.md>
**User to do:** <manual/GUI steps outstanding>
```

---

<!-- Phase entries go below -->

## Phase 1: Setup, ingest, profile (2026-10-08) — code complete, DB verification pending

**Shipped:** `requirements.txt`, `pyproject.toml` (ruff + pytest), `.env.example`, `.gitignore`; `scripts/download_data.py` (Kaggle API → GitHub fallback, idempotent, tolerates UTF-16 `access_token`), `scripts/00_create_raw_schema.sql` (9 all-text tables), `scripts/setup_postgres.ps1` (role + DB from .env), `scripts/env.ps1` (loads .env, finds psql), `scripts/load_raw.ps1` (single-transaction truncate + `\copy`), `scripts/db.py`; `tests/conftest.py`, `tests/test_raw_counts.py`; dbt scaffold `dbt/retailpulse/` (dbt_project.yml, packages.yml → dbt_utils 1.4.1, profiles.yml.example; `~/.dbt/profiles.yml` installed); `notebooks/01_eda.ipynb` part 1; `docs/data_quality_log.md` (26 quirks); README skeleton.
**Key numbers:** all 9 CSV row counts = §3a (orders 99,441 … geolocation 1,000,163); customer_unique_id 96,096; dup review_id 814 extra rows / 789 distinct ids; 547 multi-review orders; 610 null-category products; late share 6.77% (6,534 / 96,470) = §3a; median delivery 10.2 vs promised 23.2 d = §3a.
**Tests:** ruff ok; pytest 19 passed / 10 skipped (DB tests: Postgres not installed yet); dbt parse ok, dbt deps ok, dbt debug: config ok, connection refused (no server); notebooks: 01_eda executed headless (CSV fallback source).
**Deferred:** raw load into Postgres, DB pytest, `dbt debug` connection — PostgreSQL not installed on this machine (user step).
**Decisions:** raw tables keep source column spelling; EDA reads Postgres when reachable, else CSVs (identical text data). Phase 2 flag: dbt `unique` on review_id returns 789 rows (one per duplicated value), not 814 — PLAN Phase 2 test_core_marts should expect 789.
**User to do:** install PostgreSQL (EDB), set `.env` password, run `setup_postgres.ps1` + `load_raw.ps1 -CreateSchema`, `dbt debug`, `pytest`; commit + push.
