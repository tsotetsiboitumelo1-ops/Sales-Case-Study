-- Databricks notebook source
---Checking the data---
SELECT *
FROM fnb_sales.default.sales_case_study
LIMIT 100;

---Counting the total number of records in the dataset
SELECT COUNT(*) AS total_records
FROM fnb_sales.default.sales_case_study;

---DESCRIBE shows the column names and their data types
DESCRIBE fnb_sales.default.sales_case_study;

--------------------------------------------
---Checking for missing values---
--------------------------------------------
SELECT
    COUNT(*) AS total_rows,
    SUM(CASE WHEN Date IS NULL THEN 1 ELSE 0 END) AS missing_dates,
    SUM(CASE WHEN Sales IS NULL THEN 1 ELSE 0 END) AS missing_sales,
    SUM(CASE WHEN `Cost Of Sales` IS NULL THEN 1 ELSE 0 END) 
        AS missing_cost_of_sales,
    SUM(CASE WHEN `Quantity Sold` IS NULL THEN 1 ELSE 0 END) 
        AS missing_quantity
FROM fnb_sales.default.sales_case_study;

-------------------------------------------------
---Checking for duplicates---
-----------------------------------------------
SELECT
    Date,
    COUNT(*) AS number_of_records
FROM fnb_sales.default.sales_case_study
GROUP BY Date
HAVING COUNT(*) > 1
ORDER BY Date;

---------------------------------------------
---Checking for incorrect numerical values
---------------------------------------------
SELECT *
FROM fnb_sales.default.sales_case_study
WHERE Sales < 0
   OR `Cost Of Sales` < 0
   OR `Quantity Sold` <= 0;

-- Checking the earliest and latest dates---
SELECT
    MIN(Date) AS first_date,
    MAX(Date) AS last_date,
    COUNT(DISTINCT Date) AS number_of_days
FROM fnb_sales.default.sales_case_study;

---Checking for missing dates----
SELECT
    MIN(Date) AS first_date,
    MAX(Date) AS last_date,
    COUNT(DISTINCT Date) AS number_of_dates,
    DATEDIFF(MAX(Date), MIN(Date)) + 1 AS expected_days
FROM fnb_sales.default.sales_case_study;

----Checking for unusual sales values
SELECT
    MIN(Sales) AS minimum_sales,
    MAX(Sales) AS maximum_sales,
    AVG(Sales) AS average_sales,

    MIN(`Cost Of Sales`) AS minimum_cost,
    MAX(`Cost Of Sales`) AS maximum_cost,
    AVG(`Cost Of Sales`) AS average_cost,

    MIN(`Quantity Sold`) AS minimum_quantity,
    MAX(`Quantity Sold`) AS maximum_quantity,
    AVG(`Quantity Sold`) AS average_quantity

FROM fnb_sales.default.sales_case_study;

------------------------------------------------
---Creating the cleaned table
------------------------------------------------
CREATE OR REPLACE TABLE fnb_sales.default.sales_clean AS
SELECT
    CAST(Date AS DATE) AS sale_date,

    -- Round money values to 2 decimal places
    ROUND(CAST(Sales AS DOUBLE), 2) AS sales,

    -- Round cost of sales to 2 decimal places
    ROUND(CAST(`Cost Of Sales` AS DOUBLE), 2) AS cost_of_sales,

    -- Quantity must be a whole number
    CAST(`Quantity Sold` AS INT) AS quantity_sold

FROM fnb_sales.default.sales_case_study

WHERE Date IS NOT NULL
  AND Sales IS NOT NULL
  AND `Cost Of Sales` IS NOT NULL
  AND `Quantity Sold` IS NOT NULL
  AND Sales >= 0
  AND `Cost Of Sales` >= 0
  AND `Quantity Sold` > 0;

------------------------------------------------
---INSPECTING THE CLEANED DATA---
------------------------------------------------
SELECT *
FROM fnb_sales.default.sales_clean
ORDER BY sale_date
LIMIT 100;

--CHECKING HOW MANY RECORDS REMAIN AFTER CLEANING
SELECT COUNT (*)
FROM fnb_sales.default.sales_clean;

--------------------------------------------------
---MAIN DAILY BUSINESS METRICS
-----------------------------------------------------
CREATE OR REPLACE TABLE fnb_sales.default.sales_analysis AS
SELECT
    sale_date,
    sales,
    cost_of_sales,
    quantity_sold,
--DAILY SALES PRICE UNIT = SALES/QUANTITY SOLD
ROUND(Sales /quantity_sold, 4) AS unit_price,

---AVERAGE UNIT SALES PRICE
ROUND(AVG(sales / quantity_sold) OVER (), 4) AS avg_unit_price,

--GROSS PROFIT = (SALES − COST OF SALES) ÷ SALES × 100
ROUND((sales - cost_of_sales) / sales * 100, 2) AS gross_profit,

---DAILY SELLING PRICE PER UNIT 
ROUND(sales / quantity_sold, 4) AS daily_unit_price,

--UNIT COST
ROUND(cost_of_sales / quantity_sold, 4) AS unit_cost,

--GROSS PROFIT RAND--- RAND GROSS PROFIT FOR THE DAY
ROUND(sales - cost_of_sales, 2) AS gross_profit_rand,

--GROSS PROFIT PERCENTAGE = (UNIT PRICE - UNIT COST) ÷ UNIT PRICE × 100
ROUND(((sales/quantity_sold) - (cost_of_sales/quantity_sold)) / (sales/quantity_sold) * 100, 2) AS gross_profit_percentage, 

--GROSS PROFIT EARNED ON EACH UNIT
ROUND((sales/quantity_sold) - (cost_of_sales/quantity_sold), 4) AS gross_profit_per_unit

FROM fnb_sales.default.sales_clean;

--INSPECTING THE CALCULATED RESULTS
SELECT *
FROM fnb_sales.default.sales_analysis
ORDER BY sale_date
LIMIT 50;

-----------------------------------------------------
--CALCULATING HOW OFTEN THE STORE SOLD THE PRODUCTS AT A LOSS
SELECT 
    ROUND(SUM(gross_profit_rand) / SUM(sales) * 100, 2) AS overall_gp,
    COUNT(*) AS total_days,
    SUM(CASE WHEN gross_profit_rand < 0 THEN 1 ELSE 0 END) AS loss_making_days,
  ROUND(SUM(CASE WHEN gross_profit_rand < 0 THEN 1 ELSE 0 END) / count(*) * 100, 1) AS days_at_a_loss
FROM fnb_sales.default.sales_analysis;

--------------------------------------------------------------------
---IDENTFYING POSSIBLE PROMOTIONAL PERIODS
-------------------------------------------------------------------
---The dataset does not say whether a product was on promotion. So, we need to identify promotion periods by looking at price changes: a promotion is likely when the unit price stays clearly lower than the usual price for several days in a row.

CREATE OR REPLACE TEMP VIEW promotion_ped_results AS

WITH daily_sales AS (

    -- 1. Create one row per sales date.
    -- Calculate the weighted average unit price for each day.
    SELECT
        CAST(sale_date AS DATE) AS sales_date,

        SUM(sales) AS daily_sales,
        SUM(quantity_sold) AS daily_quantity_sold,

        SUM(sales) / NULLIF(SUM(quantity_sold), 0) AS daily_unit_price

    FROM fnb_sales.default.sales_analysis

    WHERE sale_date IS NOT NULL
      AND sales > 0
      AND quantity_sold > 0

    GROUP BY
        CAST(sale_date AS DATE)
),

usual_price AS (

    -- 2. Find the median daily unit price.
    -- This becomes the normal/usual price.
    SELECT
        percentile_approx(daily_unit_price, 0.5) AS normal_unit_price

    FROM daily_sales
),

daily_promo_flags AS (

    -- 3. Flag a date as a promotion day when daily unit price
    -- is at least 10% below the normal/median unit price.
    SELECT
        d.sales_date,
        d.daily_sales,
        d.daily_quantity_sold,
        d.daily_unit_price,
        u.normal_unit_price,

        (
            (u.normal_unit_price - d.daily_unit_price)
            / NULLIF(u.normal_unit_price, 0)
        ) AS discount_pct,

        CASE
            WHEN d.daily_unit_price <= u.normal_unit_price * 0.90
            THEN 1
            ELSE 0
        END AS is_promo_day

    FROM daily_sales d

    CROSS JOIN usual_price u
),

candidate_promo_days AS (

    -- 4. Keep possible promotion days only.
    -- Get the previous promotion date.
    SELECT
        sales_date,
        daily_sales,
        daily_quantity_sold,
        daily_unit_price,
        normal_unit_price,
        discount_pct,

        LAG(sales_date) OVER (
            ORDER BY sales_date
        ) AS previous_promo_date

    FROM daily_promo_flags

    WHERE is_promo_day = 1
),

promo_period_starts AS (

    -- 5. A new promotion period starts if:
    -- - it is the first promo date, or
    -- - the previous promo date was more than one day ago.
    SELECT
        *,

        CASE
            WHEN previous_promo_date IS NULL THEN 1

            WHEN DATEDIFF(sales_date, previous_promo_date) > 1 THEN 1

            ELSE 0
        END AS starts_new_promo_period

    FROM candidate_promo_days
),

promo_days_grouped AS (

    -- 6. Give each consecutive promotion period its own ID.
    SELECT
        *,

        SUM(starts_new_promo_period) OVER (
            ORDER BY sales_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS promo_period_id

    FROM promo_period_starts
),

promotion_periods AS (

    -- 7. Summarise each promotion period.
    SELECT
        promo_period_id,

        MIN(sales_date) AS promo_start_date,
        MAX(sales_date) AS promo_end_date,
        COUNT(*) AS promo_days,

        AVG(normal_unit_price) AS normal_unit_price,
        AVG(daily_unit_price) AS promo_unit_price,

        AVG(daily_quantity_sold) AS avg_promo_daily_quantity,

        AVG(discount_pct) AS avg_discount_pct

    FROM promo_days_grouped

    GROUP BY
        promo_period_id

    -- Ignore one-day changes, which could be data issues.
    HAVING COUNT(*) >= 2
),

normal_period_baseline AS (

    -- 8. Find normal average daily quantity sold.
    -- Only use days that were NOT marked as promotions.
    SELECT
        AVG(daily_quantity_sold) AS avg_normal_daily_quantity

    FROM daily_promo_flags

    WHERE is_promo_day = 0
),

promotion_periods_with_ped AS (

    -- 9. Calculate PED for every inferred promotion period.
    SELECT
        p.promo_period_id,
        p.promo_start_date,
        p.promo_end_date,
        p.promo_days,

        p.normal_unit_price,
        p.promo_unit_price,
        p.avg_discount_pct,

        n.avg_normal_daily_quantity,
        p.avg_promo_daily_quantity,

        -- Midpoint percentage change in quantity
        (
            p.avg_promo_daily_quantity - n.avg_normal_daily_quantity
        )
        / NULLIF(
            (
                p.avg_promo_daily_quantity
                + n.avg_normal_daily_quantity
            ) / 2,
            0
        ) AS pct_change_quantity,

        -- Midpoint percentage change in price
        (
            p.promo_unit_price - p.normal_unit_price
        )
        / NULLIF(
            (
                p.promo_unit_price
                + p.normal_unit_price
            ) / 2,
            0
        ) AS pct_change_price,

        -- Price Elasticity of Demand:
        -- % change in quantity divided by % change in price
        (
            (
                p.avg_promo_daily_quantity - n.avg_normal_daily_quantity
            )
            / NULLIF(
                (
                    p.avg_promo_daily_quantity
                    + n.avg_normal_daily_quantity
                ) / 2,
                0
            )
        )
        /
        NULLIF(
            (
                p.promo_unit_price - p.normal_unit_price
            )
            / NULLIF(
                (
                    p.promo_unit_price
                    + p.normal_unit_price
                ) / 2,
                0
            ),
            0
        ) AS price_elasticity_of_demand

    FROM promotion_periods p

    CROSS JOIN normal_period_baseline n
),

ranked_promotions AS (

    -- 10. Choose any three periods.
    -- This version selects the three longest promotion periods.
    SELECT
        *,

        ROW_NUMBER() OVER (
            ORDER BY
                promo_days DESC,
                promo_start_date
        ) AS promotion_number

    FROM promotion_periods_with_ped
)

SELECT
    promotion_number,

    promo_start_date,
    promo_end_date,
    promo_days,

    ROUND(normal_unit_price, 2) AS normal_unit_price,
    ROUND(promo_unit_price, 2) AS promotion_unit_price,

    ROUND(avg_discount_pct * 100, 2) AS average_discount_percent,

    ROUND(avg_normal_daily_quantity, 2) AS average_normal_daily_quantity,
    ROUND(avg_promo_daily_quantity, 2) AS average_promotion_daily_quantity,

    ROUND(pct_change_quantity * 100, 2) AS percentage_change_in_quantity,
    ROUND(pct_change_price * 100, 2) AS percentage_change_in_price,

    ROUND(price_elasticity_of_demand, 2) AS price_elasticity_of_demand,

    CASE
        WHEN price_elasticity_of_demand IS NULL
            THEN 'PED cannot be calculated'

        WHEN ABS(price_elasticity_of_demand) > 1
            THEN 'Elastic demand'

        WHEN ABS(price_elasticity_of_demand) < 1
            THEN 'Inelastic demand'

        ELSE 'Unit elastic demand'
    END AS elasticity_interpretation

FROM ranked_promotions

WHERE promotion_number <= 3

ORDER BY promotion_number;
-----------------------------------------------
--INSPECTING THE CREATED PED TABLE
-----------------------------------------------
SELECT *
FROM promotion_ped_results;





