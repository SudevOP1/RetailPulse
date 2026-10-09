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

## Phase 2: dbt star schema + 25+ data-quality tests (2026-10-09)

**Shipped:** `macros/generate_schema_name.sql` (schemas `staging` / `intermediate` / `marts` / `dbt_test__audit`, no `dev_` prefix); seeds `state_region.csv` (27 UFs → 5 regions), `category_translation_patch.csv` (2 rows) + `_seeds.yml`; `_sources.yml` (9 raw tables); 9 staging views `stg_olist__*` + `_staging.yml`; 4 intermediate views (`int_order_items_agg`, `int_order_payments_agg`, `int_order_reviews_latest`, `int_zip_geolocation`) + `_intermediate.yml`; core marts `dim_date`, `dim_customer`, `dim_seller`, `dim_product`, `fact_orders`, `fact_order_items` + `_core.yml` (description on every model and column); singular tests `assert_delivered_after_purchase`, `assert_payments_match_items`; `tests/test_core_marts.py`; `docs/erd.dbml`; DQ log #27–31; `dbt docs generate` (catalog written).
**Key numbers:** fact_orders 99,441 · fact_order_items 112,650 · dim_customer 96,096 · dim_seller 3,095 · dim_product 32,951 · dim_date 852 · int_order_reviews_latest 98,673. Dup-review test: 789 values / **814 extra rows** (§3a 814). Late share 6.77% (6,534 / 96,470) = §3a; 1-star late vs on-time 53.8% vs 6.6% = §3a. Delivered-item GMV R$13,221,498 (§3a R$13.2M). 73 translated categories + `unknown` (610). Payments-vs-items mismatch 250 orders (0.25%). Preview for Phase 3: repeat customers 2,801 / 93,358 = 3.00% (§3a denominator 93,350; 8-customer gap to check there).
**Tests:** ruff ok; pytest 51 passed / 0 skipped (incl. Phase 1 DB tests, now running against Postgres 18); dbt build **PASS=77 WARN=2 ERROR=0** (79 nodes: 58 data tests, 13 views, 6 tables, 2 seeds). WARNs = intentional `unique_stg_olist__reviews_review_id` (789) and `assert_payments_match_items` (250). All 30 planned tests (PLAN §8) present, plus 28 extra key/seed tests.
**Deferred:** lineage screenshot (`dbt docs serve`) and ERD PNG (dbdiagram.io): user-only.
**Decisions:** natural keys as dim keys (`customer_key` = customer_unique_id, `seller_key` = seller_id, `product_key` = product_id; no SCD, readable in drill-through); `dim_date.date_key` int yyyymmdd. `category_en` is null (not 'unknown') when a real category lacks a translation, so test #27 genuinely depends on the patch seed. Dup-review stored failures aliased to `dbt_test__audit.dup_review_ids`. `assert_payments_match_items` warns > 0 and errors at ≥ 1% of orders; orders with no items are excluded from it. `fact_order_items` takes status / is_late / review from `fact_orders` (one definition). Phase 1 marked Done: Postgres now installed and raw counts tests pass.
**User to do:** (1) `dbt docs serve` → screenshot lineage → `docs/dbt_lineage.png`; (2) paste `docs/erd.dbml` into dbdiagram.io → export `docs/erd.png`; (3) commit + push.
