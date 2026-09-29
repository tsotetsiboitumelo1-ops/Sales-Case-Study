-- Databricks notebook source
------------------------------------------------------------
-- FINAL TABLE
------------------------------------------------------------
CREATE OR REPLACE TABLE fnb_sales.default.sales_dashboard AS

WITH daily AS (
    -- 1. One row per date (safe even if a date appears twice)
    SELECT
        CAST(sale_date AS DATE) AS sale_date,
        SUM(sales)              AS sales,
        SUM(cost_of_sales)      AS cost_of_sales,
        SUM(quantity_sold)      AS quantity_sold
    FROM fnb_sales.default.sales_clean
    WHERE sales > 0 AND quantity_sold > 0
    GROUP BY CAST(sale_date AS DATE)
),

usual_price AS (
    -- 2. Normal price = median daily unit price
    SELECT percentile_approx(sales / quantity_sold, 0.5) AS normal_unit_price
    FROM daily
),

metrics AS (
    -- 3. Metrics 1-4 + extras
    SELECT
        d.sale_date,
        d.sales,
        d.cost_of_sales,
        d.quantity_sold,

        ROUND(d.sales / d.quantity_sold, 4)                         AS daily_unit_price,
        ROUND(d.cost_of_sales / d.quantity_sold, 4)                 AS unit_cost,
        ROUND(d.sales - d.cost_of_sales, 2)                         AS gross_profit_rand,
        ROUND((d.sales - d.cost_of_sales) / d.sales * 100, 2)       AS gross_profit_pct,
        ROUND((d.sales - d.cost_of_sales) / d.quantity_sold, 4)     AS gross_profit_per_unit,

        -- Average unit price: simple average of daily prices and volume-weighted
        ROUND(AVG(d.sales / d.quantity_sold) OVER (), 4)            AS avg_unit_price,
        ROUND(SUM(d.sales) OVER () / SUM(d.quantity_sold) OVER (), 4) AS weighted_avg_unit_price,

        ROUND(u.normal_unit_price, 4)                               AS normal_unit_price,
        ROUND((u.normal_unit_price - d.sales / d.quantity_sold)
              / u.normal_unit_price * 100, 2)                       AS discount_pct,

        CASE WHEN d.sales - d.cost_of_sales < 0 THEN 1 ELSE 0 END   AS is_loss_making,
        CASE WHEN d.sales / d.quantity_sold <= u.normal_unit_price * 0.90
             THEN 1 ELSE 0 END                                      AS is_promo_candidate,

        -- Calendar fields for dashboards
        YEAR(d.sale_date)                AS sale_year,
        MONTH(d.sale_date)               AS sale_month,
        date_format(d.sale_date, 'MMM')  AS month_name,
        WEEKOFYEAR(d.sale_date)          AS week_of_year,
        date_format(d.sale_date, 'EEEE') AS day_name
    FROM daily d
    CROSS JOIN usual_price u
),

candidate_days AS (
    -- 4. Promo candidate days + previous candidate date
    SELECT
        sale_date,
        LAG(sale_date) OVER (ORDER BY sale_date) AS previous_promo_date
    FROM metrics
    WHERE is_promo_candidate = 1
),

period_ids AS (
    -- 5. New period whenever there is a gap of more than 1 day
    SELECT
        sale_date,
        SUM(CASE WHEN previous_promo_date IS NULL
                   OR DATEDIFF(sale_date, previous_promo_date) > 1
                 THEN 1 ELSE 0 END)
            OVER (ORDER BY sale_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
            AS promo_period_id
    FROM candidate_days
),

normal_baseline AS (
    -- 6. Normal average daily quantity (non-promo days only)
    SELECT AVG(quantity_sold) AS avg_normal_daily_quantity
    FROM metrics
    WHERE is_promo_candidate = 0
),

period_summary AS (
    -- 7. Summarise each promo period (2+ days only)
    SELECT
        p.promo_period_id,
        MIN(m.sale_date)         AS promo_start_date,
        MAX(m.sale_date)         AS promo_end_date,
        COUNT(*)                 AS promo_days,
        AVG(m.daily_unit_price)  AS promo_unit_price,
        AVG(m.normal_unit_price) AS period_normal_price,
        AVG(m.quantity_sold)     AS avg_promo_daily_quantity,
        AVG(m.discount_pct)      AS avg_discount_pct
    FROM period_ids p
    JOIN metrics m ON m.sale_date = p.sale_date
    GROUP BY p.promo_period_id
    HAVING COUNT(*) >= 2
),

period_ped AS (
    -- 8. Midpoint PED per period + rank by length
    SELECT
        s.*,
        n.avg_normal_daily_quantity,
        ((s.avg_promo_daily_quantity - n.avg_normal_daily_quantity)
            / ((s.avg_promo_daily_quantity + n.avg_normal_daily_quantity) / 2))
        /
        NULLIF((s.promo_unit_price - s.period_normal_price)
            / ((s.promo_unit_price + s.period_normal_price) / 2), 0)
            AS price_elasticity_of_demand,
        ROW_NUMBER() OVER (ORDER BY s.promo_days DESC, s.promo_start_date) AS promotion_number
    FROM period_summary s
    CROSS JOIN normal_baseline n
)

-- 9. Final table: every day, with promo/PED info attached where relevant
SELECT
    m.*,

    CASE WHEN pp.promo_period_id IS NOT NULL THEN 'Promotion' ELSE 'Normal' END AS price_type,
    pp.promo_period_id,
    pp.promotion_number,
    CASE WHEN pp.promotion_number <= 3 THEN 1 ELSE 0 END AS is_top3_promo,
    pp.promo_start_date,
    pp.promo_end_date,
    pp.promo_days,
    ROUND(pp.avg_normal_daily_quantity, 2)      AS period_avg_normal_daily_qty,
    ROUND(pp.avg_promo_daily_quantity, 2)       AS period_avg_promo_daily_qty,
    ROUND(pp.price_elasticity_of_demand, 2)     AS price_elasticity_of_demand,
    CASE
        WHEN pp.promo_period_id IS NULL                 THEN NULL
        WHEN pp.price_elasticity_of_demand IS NULL      THEN 'PED cannot be calculated'
        WHEN ABS(pp.price_elasticity_of_demand) > 1     THEN 'Elastic demand'
        WHEN ABS(pp.price_elasticity_of_demand) < 1     THEN 'Inelastic demand'
        ELSE 'Unit elastic demand'
    END AS elasticity_interpretation

FROM metrics m
LEFT JOIN period_ids  pi ON pi.sale_date = m.sale_date
LEFT JOIN period_ped  pp ON pp.promo_period_id = pi.promo_period_id;

-- Inspecting the table
SELECT * 
FROM fnb_sales.default.sales_dashboard 
ORDER BY sale_date 
LIMIT 100;