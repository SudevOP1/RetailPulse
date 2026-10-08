# CLAUDE.md

Guidance for Claude Code working in this repo.

## What this is

**RetailPulse**: a portfolio analytics project on the Olist Brazilian e-commerce dataset (Kaggle `olistbr/brazilian-ecommerce`, 9 CSVs, 99,441 orders, 2016–2018). The owner is a final-year student building it to back four resume bullets. **The resume bullets are the spec**: every phase exists to make one of them true and verifiable.

- `PLAN.md`: full build plan. §0 = status table + rules, §8 = phase-by-phase tasks, §3a = verified sanity-check numbers, §9 = how each resume number is measured.
- `PROGRESS.md`: append-only log, one entry per completed phase.

Resume bullets (do not change the wording; if computed numbers differ, report it and the resume gets updated, never the data):

1. Modeled 100K Olist orders from 9 raw tables into a PostgreSQL star schema with dbt (2 fact, 4 dimension tables), enforcing 25+ data-quality tests that flagged duplicate reviews. → **Phase 2**
2. Late deliveries (6.8% of orders) carry an 8x higher 1-star rate (54% vs 7%), via z-test and controlled logistic regression; A/B test sized via power analysis. → **Phase 4**
3. SQL (CTEs, window functions) for KPIs, cohort retention, RFM, category Pareto: 3% repeat-purchase rate, 17 of 73 categories = 80% of revenue. → **Phase 3**
4. 4-page Power BI dashboard, 15 DAX measures, seller drill-through, plus KPI dictionary and 1-page memo with 4 quantified recommendations. → **Phases 5–6**

## Stack

PostgreSQL 16+ (local, Windows) · dbt Core + dbt-postgres + dbt_utils · Python 3.12 (pandas, SciPy, statsmodels, scikit-learn, Matplotlib, Seaborn, SQLAlchemy, psycopg) · Jupyter · Power BI Desktop · Excel (Power Query) · ruff · pytest.

## Layout (target; see PLAN.md §6)

- `scripts/`: download, raw schema SQL, `load_raw.ps1`, `db.py` (shared engine from `.env`), exports, stats helpers
- `dbt/retailpulse/`: dbt project. `models/staging` (views) → `models/intermediate` (views) → `models/marts/core` (2 facts, 4 dims, tables) → `models/marts/analytics` (tables). Seeds in `seeds/`, singular tests in `tests/`.
- `tests/`: pytest. DB-dependent tests skip cleanly if Postgres is unreachable.
- `notebooks/`: `01_eda`, `02_late_delivery_stats`, `03_ab_test_design`
- `powerbi/`, `excel/`: binaries built by the user + `BUILD_GUIDE.md`, `dax_measures.md`, `theme.json` written by Claude
- `docs/`: DQ log, KPI dictionary, insight memo, ERD, lineage, `img/`
- `data/raw/`: **gitignored**. Never commit raw CSVs (licence CC BY-NC-SA 4.0; ship the download script).

## Conventions

- **ELT**: raw tables are all `text`; all typing/casting happens in dbt staging.
- Staging: rename, cast, trim, lowercase categoricals, **no joins** (exception: product category translation + patch seed).
- dbt naming: `stg_olist__<table>`, `int_<thing>`, `dim_<entity>`, `fact_<grain>`. SQL lowercase, CTE-first, `{{ ref() }}` / `{{ source() }}` only, never hardcoded schemas.
- Definitions that must stay consistent everywhere (SQL, DAX, notebooks, memo): late = `delivered::date > estimated::date` on delivered orders with a delivered date; customer = `customer_unique_id`; GMV = sum of item `price` (no freight); review = latest per order; trend window Jan 2017 – Aug 2018. Record any new definition in `docs/kpi_definitions.md`.
- Every quirk/decision about the data goes in `docs/data_quality_log.md`.
- Python: read DB creds from `.env` via `scripts/db.py`; no credentials in code or notebooks. Notebooks must run top-to-bottom headless.
- Windows paths and PowerShell for scripts (`.ps1`); Python scripts must be cross-platform.

## Commands

Run from repo root with the venv active (`.\.venv\Scripts\Activate.ps1`) unless noted.

```powershell
pip install -r requirements.txt
python scripts/download_data.py
psql -f scripts/00_create_raw_schema.sql      # uses PG* env vars
.\scripts\load_raw.ps1
cd dbt/retailpulse; dbt deps; dbt build; cd ../..   # build = run + test + seed
dbt build -s staging intermediate              # subset (from dbt/retailpulse)
dbt docs generate                              # do NOT run `dbt docs serve` (long-running)
python scripts/export_marts.py
ruff check .
pytest
jupyter nbconvert --to notebook --execute --inplace notebooks/<name>.ipynb
```

## Workflow: "implement phase N" (or similar)

Follow this order every time:

1. **Ask first.** Read `PLAN.md` + `PROGRESS.md`, then ask any clarifying questions up front with AskUserQuestion before writing code. Skip only if nothing is genuinely ambiguous.
2. **Implement the entire phase in one pass**: every task, model, notebook, script, doc and test listed under that phase in PLAN.md §8. No stop-and-verify loop between tasks (this supersedes any per-step checkpointing implied elsewhere in PLAN.md). Don't pull in work from later phases.
3. **Run all relevant tests and fix failures before finishing:**
   - `ruff check .` (always)
   - `pytest` (always; DB tests must actually run, not skip, if Postgres is up)
   - `dbt build` from `dbt/retailpulse/` whenever dbt models/seeds/tests changed. Expected: ERROR=0; WARN only on the intentional ones (dup `review_id`, payments-vs-items).
   - `jupyter nbconvert --execute` on every notebook touched.
   - Tests yes; **long-running/interactive things no**: don't launch `dbt docs serve`, Jupyter Lab, or Power BI/Excel GUIs.
4. **Finish with a summary**: what shipped, what was deferred (and why), the key numbers produced vs PLAN.md §3a, then step-by-step manual-testing instructions with exact commands and what to check. **Run every command you can yourself**; leave the user only the steps you can't do (GUI work in Power BI/Excel, screenshots, `dbt docs serve` browsing, Kaggle/GitHub auth, Loom).
5. **Bookkeeping**: append the phase note to `PROGRESS.md` (template inside that file) and update the PLAN.md §0 status table (status + date).

## Things Claude cannot do here (hand to the user with instructions)

Build/edit `.pbix` files, Excel Power Query/PivotTables, screenshots, `dbt docs serve` lineage capture, dbdiagram.io ERD export, Loom, installing PostgreSQL, Kaggle token setup, GitHub repo pinning.

## Guardrails

- Never commit `data/raw/`, `.env`, `profiles.yml`, or `dbt/retailpulse/target/`.
- Never fudge a number to match the resume. If a metric is off by more than ~1 pp from PLAN.md §3a, check definitions (status filter, null dates, latest-review logic) first, then report the real value.
- Don't destructively drop Postgres schemas other than ones this project owns (`raw`, `dev*`, `staging`, `intermediate`, `marts`, `dbt_test__audit`).
