# Data-quality log

Every quirk found in the raw Olist data, the decision taken, and the phase that implements it.
Numbers come from `notebooks/01_eda.ipynb` §8 (raw data as loaded, 2026-10-08) and match PLAN.md §3a.

**Decisions:** `drop` = remove rows · `keep` = retain as-is · `fix` = correct/transform · `flag` = keep but surface (test, column or note).

## Source-level

| # | Table | Quirk | Evidence | Decision | Implemented in |
|---|---|---|---|---|---|
| 1 | all | Loaded as `text` on purpose (ELT): values are not validated at load | `scripts/00_create_raw_schema.sql` | **keep**: all typing/casting in dbt staging | Phase 1 / 2 |
| 2 | order_reviews | Comment fields contain embedded newlines inside quotes; `wc -l` overcounts rows | 99,224 rows parsed vs more physical lines | **keep**: `\copy … CSV` parses quoted newlines; row-count test guards it | Phase 1 (`load_raw.ps1`, `test_raw_counts.py`) |
| 3 | product_category_name_translation | File starts with a UTF-8 BOM; Kaggle copies use CRLF line endings | header bytes `EF BB BF` | **keep**: `HEADER true` skips the first line, CSV mode accepts CRLF | Phase 1 |
| 4 | products | Misspelled source columns `product_name_lenght`, `product_description_lenght` | raw header | **fix**: rename to `*_length` in `stg_olist__products` (raw keeps source spelling) | Phase 2 |
| 5 | customers, sellers, geolocation | Zip prefixes have leading zeros (23,995 customer zips start with `0`) | 5-char strings | **keep** as text, never cast to int | Phase 2 |

## Keys and grain

| # | Table | Quirk | Evidence | Decision | Implemented in |
|---|---|---|---|---|---|
| 6 | customers | `customer_id` is **per order**; the real person is `customer_unique_id` | 99,441 `customer_id` vs 96,096 `customer_unique_id` | **fix**: `dim_customer` at `customer_unique_id` grain; "customer" means `customer_unique_id` everywhere | Phase 2 |
| 7 | order_reviews | Duplicate `review_id`: 814 extra rows across 789 distinct ids (same review attached to several orders) | `review_id.duplicated()` = 814 | **flag**: `unique` test on `stg_olist__reviews.review_id` with `severity: warn` + `store_failures`. Note: dbt's `unique` test returns one row **per duplicated value**, so it will report **789** failures, not 814. Phase 2 must assert 789 (or count rows another way) | Phase 2 (test #15) |
| 8 | order_reviews | 547 orders have more than one review | `groupby(order_id).size() > 1` | **fix**: keep latest per order (`row_number() over (partition by order_id order by review_answer_timestamp desc) = 1`) in `int_order_reviews_latest` | Phase 2 |
| 9 | order_reviews | 768 orders have no review | anti-join orders → reviews | **keep**: `review_score` null; review metrics use orders with a review only | Phase 2 / 4 |
| 10 | geolocation | 1,000,163 rows but only 19,015 zip prefixes; 261,831 exact-duplicate rows | `nunique`, `duplicated()` | **fix**: `int_zip_geolocation` = `avg(lat), avg(lng)` per prefix; never join the raw table | Phase 2 |
| 11 | geolocation | 31 points have latitude outside Brazil's range [−34, 6] | bounds check | **fix**: exclude out-of-bounds points before averaging (and lng outside [−74, −34]) | Phase 2 |
| 12 | order_items | Up to 21 items per order; 1,278 orders have more than one seller | `order_item_id` max, seller `nunique` | **keep**: `fact_order_items` at item grain; `sellers_count` on `fact_orders` | Phase 2 |

## Missing / inconsistent values

| # | Table | Quirk | Evidence | Decision | Implemented in |
|---|---|---|---|---|---|
| 13 | products | 610 products with null category (same rows also miss name/description length and photo count) | null % = 1.85 | **fix**: `coalesce(category_en, 'unknown')`; **excluded** from the category Pareto (17 of 73); KPI dictionary records the choice | Phase 2 / 3 |
| 14 | product_category_name_translation | 2 categories have no English name: `pc_gamer`, `portateis_cozinha_e_preparadores_de_alimentos` | set difference | **fix**: seed `category_translation_patch.csv`; `not_null` test on `dim_product.category_en` documents the fix | Phase 2 |
| 15 | products | 2 products missing weight and dimensions | null counts | **keep**: null `weight_g` / `volume_cm3` | Phase 2 |
| 16 | orders | 8 orders `delivered` with no delivered date | status vs null date | **keep**: `is_late` null; excluded from late-delivery share (denominator 96,470) | Phase 2 |
| 17 | orders | 160 orders with null `order_approved_at` | null count | **keep**: no metric depends on approval time | Phase 2 |
| 18 | orders | 166 orders handed to the carrier **before** purchase timestamp | carrier date < purchase | **flag**: kept; no metric uses carrier date. 0 orders are delivered before purchase (singular test `assert_delivered_after_purchase` guards this) | Phase 2 |
| 19 | orders / order_items | 775 orders have no items (mostly canceled/unavailable) | anti-join | **keep** in `fact_orders` with `items_count = 0`, `items_value = 0`; contribute 0 to GMV | Phase 2 |
| 20 | orders / order_payments | 1 order has no payment row | anti-join | **flag**: `payment_value` null; covered by warn-level `assert_payments_match_items` | Phase 2 |
| 21 | order_payments | 3 payments typed `not_defined`; 9 payments of R$0; 2 with 0 installments | value counts | **keep**: `not_defined` is in the `accepted_values` list | Phase 2 |
| 22 | order_items | 383 items with `freight_value = 0` (free shipping) | equality check | **keep**: valid; `accepted_range` min 0 | Phase 2 |
| 23 | order_items | 4 items have `shipping_limit_date` in 2020 (data entry error) | max = 2020-04-09 | **keep**: no metric uses `shipping_limit_date` | Phase 2 |
| 24 | order_reviews | 58.7% of reviews have no comment message (41.3% have one, in Portuguese); 88.3% no title | null % | **keep**: `has_review_comment` flag on `fact_orders`; text NLP is stretch only | Phase 2 |

## Time coverage

| # | Table | Quirk | Evidence | Decision | Implemented in |
|---|---|---|---|---|---|
| 25 | orders | Purchases run 2016-09-04 → 2018-10-17; Sep–Dec 2016 sparse (329 orders, **0** in Nov 2016), Sep–Oct 2018 truncated (20 orders) | orders-per-month chart | **keep** all rows in tables; **filter** trend charts and monthly KPIs to Jan 2017 – Aug 2018 | Phase 3 / 5 |
| 26 | orders | Delivery estimates are heavily padded: median actual 10.2 d vs promised 23.2 d, yet 6.77% (6,534 / 96,470) arrive late | delivery histogram | **flag**: context for the late-delivery analysis and memo; late = `delivered::date > estimated::date` | Phase 4 / 6 |

## Found / verified in Phase 2 (dbt build, 2026-10-09)

| # | Table | Quirk | Evidence | Decision | Implemented in |
|---|---|---|---|---|---|
| 27 | order_reviews | Test #15 (`unique` on `stg_olist__reviews.review_id`, warn) fires as designed | 789 failing values stored in `dbt_test__audit.dup_review_ids`; `sum(n_records) - count(*)` = **814** extra rows | **flag** confirmed; (review_id, order_id) pairs are unique, so each duplicate is one review linked to several orders. `int_order_reviews_latest` leaves 98,673 orders with exactly one review | Phase 2 |
| 28 | geolocation | 5 zip prefixes (16 points) lie entirely outside Brazil's bounding box and vanish after #11's filter | 19,015 → 19,010 prefixes in `int_zip_geolocation` | **keep**: affected customers/sellers get null lat/lng | Phase 2 |
| 29 | customers, sellers | Zip prefix with no geolocation at all | 269 of 96,096 customers, 7 of 3,095 sellers have null lat/lng | **keep** null; maps in Power BI fall back to state | Phase 2 |
| 30 | order_payments | Payment ≠ items + freight by more than R$1 on orders with items | 250 orders (0.25%; 247 delivered, mean +R$10.9 — instalment interest) stored in `dbt_test__audit.assert_payments_match_items` | **flag**: singular test warns above 0, errors only at ≥ 1% (994 orders). GMV uses item price, not payments | Phase 2 (test #30) |
| 31 | products | 2 untranslated categories | `not_null` on `dim_product.category_en` passes only because of the patch seed (a non-null category without a translation stays null by design) | **fix** confirmed: 73 English categories + `unknown` (610 products) | Phase 2 (test #27) |
