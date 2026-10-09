# KPI definitions

Single source of truth for every metric used in SQL (`marts/analytics`), DAX, notebooks and the memo.
Started in Phase 3 with the definitions the analytics marts depend on. Phase 6 expands this into the full
12-KPI dictionary (business question, SQL + DAX formula, owner, caveat).

## Shared definitions

| Term | Definition | Notes |
|---|---|---|
| Customer | `customer_unique_id` (= `customer_key` in the marts) | Olist's `customer_id` is per order; using it would make every customer a one-time buyer |
| Delivered order | `order_status = 'delivered'` (96,478 orders) | 8 of these have no delivered date |
| GMV ("revenue" on the resume) | Σ item `price` on **delivered** orders, no freight | R$13,221,498. Item GMV, not Olist revenue (commission unknown). Chosen in Phase 3 so GMV, AOV, repeat rate and late/review metrics share one population |
| AOV | GMV / delivered orders | R$137.04 |
| Orders (volume) | All orders placed, any status | Used for order counts and YoY growth (22,968 → 53,991 Jan–Aug, +135%) |
| Late | `delivered_customer_at::date > estimated_delivery_at::date`, delivered orders with a delivered date only | Undelivered orders excluded (survivorship bias). Late share 6.77% (6,534 / 96,470) |
| On-time rate | 1 − late share, same denominator | |
| Review | Latest review per order (`int_order_reviews_latest`) | Resolves duplicate reviews |
| 1-star rate | Orders whose latest review = 1 / orders with a review | Delivered orders in the marts |
| Freight share | freight / (item price + freight), delivered orders | 14.26% overall |
| Trend window | Purchase months Jan 2017 – Aug 2018 | Sep–Dec 2016 sparse, Sep–Oct 2018 truncated (DQ log #25). `kpi_monthly` is limited to it; `kpi_summary` covers all data |

## Phase 3 metric decisions

### Repeat-purchase rate: 3.00%

`customer_unique_id` with ≥ 2 delivered orders / `customer_unique_id` with ≥ 1 delivered order
= **2,801 / 93,358 = 3.00%** (`marts.kpi_summary`).
PLAN §3a used 93,350 as the denominator: it counted only delivered orders *with a delivered date*. The 8
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

| Segment | Rule | Customers |
|---|---|---:|
| Champions | f_flag and R ≥ 3 | 1,809 |
| Loyal-lapsing | f_flag and R ≤ 2 | 992 |
| New high-value | one order, R ≥ 4, M ≥ 4 | 14,479 |
| New/promising | one order, R ≥ 4, M ≤ 3 | 21,662 |
| At-risk high-value | one order, R ≤ 3, M ≥ 4 | 20,727 |
| Hibernating | one order, R ≤ 3, M ≤ 3 | 33,689 |

### Category Pareto: 17 of 73

Delivered item GMV by category. The 610 products with a null category (`unknown`, R$170K delivered GMV)
are **excluded**, leaving the 73 real categories. Result: **17 of 73 categories make 80% of GMV**.
Keeping `unknown` as a 74th category gives 18 of 74. All-status GMV also gives 17 of 73.

Count = categories needed to reach 80%, i.e. those whose cumulative share *before* them is < 80%
(= `count(cum_share <= 0.8) + 1`). `abc_class`: A = needed to reach 80%, B = needed to reach 95%, C = rest.

### Seller scorecard and tier rule

Population: sellers with ≥ 20 delivered seller-orders (804 sellers). A seller-order is one (seller, order)
pair, so an order with two sellers counts for both.

| Tier | Rule | Sellers |
|---|---|---:|
| C | worst late-rate decile (`ntile(10)` = 10) **or** 1-star rate ≥ 2× marketplace 1-star rate | 99 |
| A | not C, GMV `percent_rank ≥ 0.8` **and** late rate ≤ median scorecard seller | 60 |
| B | everyone else | 645 |

Worst late-rate decile: 80 sellers = 5.2% of all delivered seller-orders but 13.2% of late seller-orders
(PLAN §3a: 82 sellers, 5.3% / 13.3%, from a slightly different seller filter).
