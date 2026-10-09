# KPI definitions

Single source of truth for every metric used in SQL (`marts/analytics`), DAX, notebooks and the memo.
Started in Phase 3 with the definitions the analytics marts depend on. Phase 6 expands this into the full
12-KPI dictionary (business question, SQL + DAX formula, owner, caveat).

## Shared definitions

| Term                          | Definition                                                                                               | Notes                                                                                                                                                   |
| ----------------------------- | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Customer                      | `customer_unique_id` (= `customer_key` in the marts)                                                     | Olist's `customer_id` is per order; using it would make every customer a one-time buyer                                                                 |
| Delivered order               | `order_status = 'delivered'` (96,478 orders)                                                             | 8 of these have no delivered date                                                                                                                       |
| GMV ("revenue" on the resume) | Σ item `price` on **delivered** orders, no freight                                                       | R$13,221,498. Item GMV, not Olist revenue (commission unknown). Chosen in Phase 3 so GMV, AOV, repeat rate and late/review metrics share one population |
| AOV                           | GMV / delivered orders                                                                                   | R$137.04                                                                                                                                                |
| Orders (volume)               | All orders placed, any status                                                                            | Used for order counts and YoY growth (22,968 → 53,991 Jan–Aug, +135%)                                                                                   |
| Late                          | `delivered_customer_at::date > estimated_delivery_at::date`, delivered orders with a delivered date only | Undelivered orders excluded (survivorship bias). Late share 6.77% (6,534 / 96,470)                                                                      |
| On-time rate                  | 1 − late share, same denominator                                                                         |                                                                                                                                                         |
| Review                        | Latest review per order (`int_order_reviews_latest`)                                                     | Resolves duplicate reviews                                                                                                                              |
| 1-star rate                   | Orders whose latest review = 1 / orders with a review                                                    | Delivered orders in the marts                                                                                                                           |
| Freight share                 | freight / (item price + freight), delivered orders                                                       | 14.26% overall                                                                                                                                          |
| Trend window                  | Purchase months Jan 2017 – Aug 2018                                                                      | Sep–Dec 2016 sparse, Sep–Oct 2018 truncated (DQ log #25). `kpi_monthly` is limited to it; `kpi_summary` covers all data                                 |

## Phase 3 metric decisions

### Repeat-purchase rate: 3.00%

`customer_unique_id` with ≥ 2 delivered orders / `customer_unique_id` with ≥ 1 delivered order
= **2,801 / 93,358 = 3.00%** (`marts.kpi_summary`).
PLAN §3a used 93,350 as the denominator: it counted only delivered orders _with a delivered date_. The 8
delivered orders without a date belong to 8 one-time customers; either way the rate rounds to 3.0%.

### Cohort retention

Active in a month = placed a non-canceled, non-unavailable order in that month. Cohort = first active month.
`retention_pct = 100 × active / cohort_size`. Average month-1 retention over cohorts with ≥ 500 customers:
**0.46%**. Cohorts outside the trend window are kept and flagged `in_trend_window = false`.

### RFM segments

One row per customer with ≥ 1 delivered order (93,358). Recency = days from the last delivered purchase to
the day after the last delivered purchase in the data. Monetary = item GMV.

**Frequency is a flag, not a quintile.** 97% of customers have exactly one delivered order, so
`NTILE(5)` on frequency would split identical values arbitrarily. `f_flag = frequency >= 2` instead.
R and M are `NTILE(5)` (5 = most recent / highest spend).

| Segment            | Rule                    | Customers |
| ------------------ | ----------------------- | --------: |
| Champions          | f_flag and R ≥ 3        |     1,809 |
| Loyal-lapsing      | f_flag and R ≤ 2        |       992 |
| New high-value     | one order, R ≥ 4, M ≥ 4 |    14,479 |
| New/promising      | one order, R ≥ 4, M ≤ 3 |    21,662 |
| At-risk high-value | one order, R ≤ 3, M ≥ 4 |    20,727 |
| Hibernating        | one order, R ≤ 3, M ≤ 3 |    33,689 |

### Category Pareto: 17 of 73

Delivered item GMV by category. The 610 products with a null category (`unknown`, R$170K delivered GMV)
are **excluded**, leaving the 73 real categories. Result: **17 of 73 categories make 80% of GMV**.
Keeping `unknown` as a 74th category gives 18 of 74. All-status GMV also gives 17 of 73.

Count = categories needed to reach 80%, i.e. those whose cumulative share _before_ them is < 80%
(= `count(cum_share <= 0.8) + 1`). `abc_class`: A = needed to reach 80%, B = needed to reach 95%, C = rest.

### Seller scorecard and tier rule

Population: sellers with ≥ 20 delivered seller-orders (804 sellers). A seller-order is one (seller, order)
pair, so an order with two sellers counts for both.

| Tier | Rule                                                                                      | Sellers |
| ---- | ----------------------------------------------------------------------------------------- | ------: |
| C    | worst late-rate decile (`ntile(10)` = 10) **or** 1-star rate ≥ 2× marketplace 1-star rate |      99 |
| A    | not C, GMV `percent_rank ≥ 0.8` **and** late rate ≤ median scorecard seller               |      60 |
| B    | everyone else                                                                             |     645 |

Worst late-rate decile: 80 sellers = 5.2% of all delivered seller-orders but 13.2% of late seller-orders
(PLAN §3a: 82 sellers, 5.3% / 13.3%, from a slightly different seller filter).

## Phase 4 statistics definitions

Source: `notebooks/02_late_delivery_stats.ipynb`, `notebooks/03_ab_test_design.ipynb`, helpers in
`scripts/stats_helpers.py`.

| Term                          | Definition                                                                                       | Value                                                                         |
| ----------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| Late share                    | late / delivered orders with a delivered date (no review filter)                                 | **6.77%** (6,534 / 96,470)                                                    |
| 1-star rate, late vs on time  | latest review = 1, among delivered orders with a delivered date **and** a review                 | **53.8% vs 6.6%** (3,431 / 6,381 vs 5,920 / 89,443)                           |
| Risk ratio ("8x")             | 1-star rate late / 1-star rate on time                                                           | **8.12x** (95% CI 7.86–8.40)                                                  |
| Odds ratio                    | raw 2×2 odds ratio; differs from the risk ratio because the outcome is common among late orders  | 16.4 (adjusted, logit: 19.1)                                                  |
| `days_late` bucket            | `delivered::date − estimated::date`, bins ≤−7, −6..0, 1–3, 4–7, 8–14, 15+ (right-closed)         | dose-response 6% → 7% → 25% → 59% → 71% → 69%                                 |
| Average marginal effect (AME) | mean over orders of P(1-star \| late) − P(1-star \| on time) from the controlled logit           | **+48.1 pp** (95% CI 46.9–49.3)                                               |
| `top_category_group`          | English category of the order's most expensive item; 15 most common kept, rest `other`           | logit control                                                                 |
| `freight_ratio`               | freight / (items + freight), per order                                                           | logit control                                                                 |
| A/B primary metric            | 1-star rate among late, reviewed orders; randomization unit `customer_unique_id`                 | baseline 54%                                                                  |
| A/B sample size               | two-sided two-proportion test, α 0.05, power 0.8, Cohen's h; `n_per_arm` = units in **each** arm | 5 pp: 1,567/arm (≈ 6.3 months); **8 pp: 612/arm (≈ 2.5 months, recommended)** |
| Eligible traffic              | late, reviewed orders per purchase month, Jan–Aug 2018 mean                                      | 499 / month (range 71–1,296)                                                  |
