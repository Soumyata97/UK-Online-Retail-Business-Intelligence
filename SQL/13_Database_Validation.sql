/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 13_Database_Validation.sql
   Purpose   : Validate the DATABASE STRUCTURE and referential integrity of the
               star schema: objects exist, keys are unique, no orphan foreign keys,
               date coverage is complete. Each check returns PASS / FAIL.
   Run order : 5th  (after 08_Data_Validation_Script.sql)
   Next step : 15_SQL_Analysis_Queries.sql, then 17_RFM_Analysis.sql
   ============================================================================= */

-- Part 1: PASS / FAIL checks ---------------------------------------------------
WITH checks AS (
    SELECT 'D01' AS check_id, 'All 8 project tables exist' AS check_name, '8' AS expected,
           (SELECT COUNT(*) FROM information_schema.tables
             WHERE (table_schema, table_name) IN (
                ('staging','raw_online_retail'), ('staging','clean_online_retail'),
                ('staging','cleaning_log'), ('dw','fact_sales'), ('dw','dim_date'),
                ('dw','dim_product'), ('dw','dim_customer'), ('dw','dim_country')))::text AS actual
    UNION ALL
    SELECT 'D02', 'Foreign keys defined on dw.fact_sales', '4',
           (SELECT COUNT(*) FROM information_schema.table_constraints
             WHERE table_schema='dw' AND table_name='fact_sales' AND constraint_type='FOREIGN KEY')::text
    UNION ALL
    SELECT 'D03', 'Orphan date_key in fact', '0',
           (SELECT COUNT(*) FROM dw.fact_sales f LEFT JOIN dw.dim_date d USING (date_key)
             WHERE d.date_key IS NULL)::text
    UNION ALL
    SELECT 'D04', 'Orphan product_key in fact', '0',
           (SELECT COUNT(*) FROM dw.fact_sales f LEFT JOIN dw.dim_product p USING (product_key)
             WHERE p.product_key IS NULL)::text
    UNION ALL
    SELECT 'D05', 'Orphan customer_key in fact', '0',
           (SELECT COUNT(*) FROM dw.fact_sales f LEFT JOIN dw.dim_customer c USING (customer_key)
             WHERE c.customer_key IS NULL)::text
    UNION ALL
    SELECT 'D06', 'Orphan country_key in fact', '0',
           (SELECT COUNT(*) FROM dw.fact_sales f LEFT JOIN dw.dim_country c USING (country_key)
             WHERE c.country_key IS NULL)::text
    UNION ALL
    SELECT 'D07', 'dim_date has every day 2010-01-01..2011-12-31', '730',
           (SELECT COUNT(DISTINCT full_date) FROM dw.dim_date
             WHERE full_date BETWEEN DATE '2010-01-01' AND DATE '2011-12-31')::text
    UNION ALL
    SELECT 'D08', 'Duplicate stock codes in dim_product', '0',
           (SELECT COUNT(*) - COUNT(DISTINCT stock_code) FROM dw.dim_product)::text
    UNION ALL
    SELECT 'D09', 'Duplicate customer_id in dim_customer', '0',
           (SELECT COUNT(customer_id) - COUNT(DISTINCT customer_id) FROM dw.dim_customer)::text
    UNION ALL
    SELECT 'D10', 'Unknown customer member exists exactly once', '1',
           (SELECT COUNT(*) FROM dw.dim_customer WHERE customer_key = 0 AND customer_id IS NULL)::text
    UNION ALL
    SELECT 'D11', 'dim_product rows = distinct stock codes in clean',
           (SELECT COUNT(DISTINCT stock_code) FROM staging.clean_online_retail)::text,
           (SELECT COUNT(*) FROM dw.dim_product)::text
    UNION ALL
    SELECT 'D12', 'dim_country rows = distinct countries in clean',
           (SELECT COUNT(DISTINCT country) FROM staging.clean_online_retail)::text,
           (SELECT COUNT(*) FROM dw.dim_country)::text
    UNION ALL
    SELECT 'D13', 'Products with blank description in dimension', '0',
           (SELECT COUNT(*) FROM dw.dim_product WHERE description IS NULL OR description = '')::text
    UNION ALL
    SELECT 'D14', 'Fact dates outside dim_date data range flag', '0',
           (SELECT COUNT(*) FROM dw.fact_sales f JOIN dw.dim_date d USING (date_key)
             WHERE NOT d.is_in_data_range)::text
)
SELECT check_id, check_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_id;

-- Part 2: row counts per table (information) ----------------------------------
SELECT 'staging.raw_online_retail'   AS table_name, COUNT(*) AS row_count FROM staging.raw_online_retail
UNION ALL SELECT 'staging.clean_online_retail', COUNT(*) FROM staging.clean_online_retail
UNION ALL SELECT 'dw.fact_sales',               COUNT(*) FROM dw.fact_sales
UNION ALL SELECT 'dw.dim_date',                 COUNT(*) FROM dw.dim_date
UNION ALL SELECT 'dw.dim_product',              COUNT(*) FROM dw.dim_product
UNION ALL SELECT 'dw.dim_customer',             COUNT(*) FROM dw.dim_customer
UNION ALL SELECT 'dw.dim_country',              COUNT(*) FROM dw.dim_country;

-- Part 3: indexes on the star schema (information) ----------------------------
SELECT schemaname, tablename, indexname
FROM pg_indexes
WHERE schemaname IN ('staging','dw')
ORDER BY schemaname, tablename, indexname;
