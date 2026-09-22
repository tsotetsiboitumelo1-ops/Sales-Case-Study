-- Databricks notebook source
---Checking the data---
SELECT *
FROM fnb_sales.default.sales_case_study
LIMIT 100;

---Counting the total number of records in the dataset
SELECT COUNT(*) AS total_records
FROM fnb_sales.default.sales_case_study;

---DESCRIBE shows the column names and their data types
DESCRIBE fnb_sales.default.sales_case_study

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

-- Checking the earliest and latest dates in the dataset
SELECT
    MIN(Date) AS first_date,
    MAX(Date) AS last_date,
    COUNT(DISTINCT Date) AS number_of_days
FROM fnb_sales.default.sales_case_study


