-- Calendar 2016-09-01 → 2018-12-31 (covers every purchase date). Mark as date table in Power BI.
with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2016-09-01' as date)",
        end_date="cast('2019-01-01' as date)"
    ) }}
)

select
    to_char(date_day, 'YYYYMMDD')::int          as date_key,
    date_day::date                              as date_day,
    extract(year from date_day)::int            as year,
    extract(quarter from date_day)::int         as quarter,
    extract(month from date_day)::int           as month,
    to_char(date_day, 'FMMonth')                as month_name,
    to_char(date_day, 'YYYY-MM')                as year_month,
    date_trunc('month', date_day)::date         as month_start,
    extract(week from date_day)::int            as iso_week,
    extract(isodow from date_day)::int          as iso_weekday,
    to_char(date_day, 'FMDay')                  as weekday_name,
    extract(isodow from date_day) in (6, 7)     as is_weekend
from spine
