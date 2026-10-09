-- RetailPulse: raw landing schema for the 9 Olist CSVs.
--
-- ELT pattern: every column is TEXT. Nothing is typed, trimmed or renamed here;
-- the CSVs land exactly as shipped (including the source's misspelled column names)
-- and all casting happens in dbt staging. A bad value can then never block a load,
-- and the raw layer stays a faithful copy of the source.
--
-- Run as the project role (PG* env vars from .env):  psql -f scripts/00_create_raw_schema.sql
-- Idempotent: drops and recreates only the raw schema owned by this project.

\set ON_ERROR_STOP on
-- Hide "schema does not exist, skipping" notices (stderr trips PowerShell 5.1 when captured).
set client_min_messages = warning;

drop schema if exists raw cascade;
create schema raw;

create table raw.orders (
    order_id                       text,
    customer_id                    text,
    order_status                   text,
    order_purchase_timestamp       text,
    order_approved_at              text,
    order_delivered_carrier_date   text,
    order_delivered_customer_date  text,
    order_estimated_delivery_date  text
);

create table raw.customers (
    customer_id                text,
    customer_unique_id         text,
    customer_zip_code_prefix   text,
    customer_city              text,
    customer_state             text
);

create table raw.order_items (
    order_id             text,
    order_item_id        text,
    product_id           text,
    seller_id            text,
    shipping_limit_date  text,
    price                text,
    freight_value        text
);

create table raw.order_payments (
    order_id              text,
    payment_sequential    text,
    payment_type          text,
    payment_installments  text,
    payment_value         text
);

create table raw.order_reviews (
    review_id                text,
    order_id                 text,
    review_score             text,
    review_comment_title     text,
    review_comment_message   text,
    review_creation_date     text,
    review_answer_timestamp  text
);

create table raw.products (
    product_id                  text,
    product_category_name       text,
    product_name_lenght         text,  -- sic: source spelling, fixed in staging
    product_description_lenght  text,  -- sic
    product_photos_qty          text,
    product_weight_g            text,
    product_length_cm           text,
    product_height_cm           text,
    product_width_cm            text
);

create table raw.sellers (
    seller_id               text,
    seller_zip_code_prefix  text,
    seller_city             text,
    seller_state            text
);

create table raw.geolocation (
    geolocation_zip_code_prefix  text,
    geolocation_lat              text,
    geolocation_lng              text,
    geolocation_city             text,
    geolocation_state            text
);

create table raw.product_category_name_translation (
    product_category_name          text,
    product_category_name_english  text
);

comment on schema raw is 'RetailPulse landing zone: Olist CSVs loaded as text by scripts/load_raw.ps1';
