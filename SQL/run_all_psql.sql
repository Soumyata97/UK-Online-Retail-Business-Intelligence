-- =============================================================================
-- run_all_psql.sql  (OPTIONAL - for the pgAdmin "PSQL Tool" or psql, NOT the Query Tool)
-- Runs the whole pipeline in the correct order in one go.
--
-- 1. Create the database online_retail_bi in pgAdmin first (START_HERE step 4).
-- 2. Right-click online_retail_bi > PSQL Tool.
-- 3. Change directory to the project's SQL folder (forward slashes):
--        \cd 'C:/Projects/UK-Online-Retail-Business-Intelligence/SQL'
-- 4. Run:   \i run_all_psql.sql
-- Tested by the author with psql on PostgreSQL 16.15 (the same \i / \copy commands).
-- =============================================================================
\set ON_ERROR_STOP on
\echo '1/8  Schema and raw table'
\i 10_Database_Schema.sql
\echo '2/8  Importing raw CSV (541,909 rows expected)'
\copy staging.raw_online_retail FROM '../Dataset/raw/online_retail_raw.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\echo '3/8  Tables'
\i 11_Table_Creation.sql
\echo '4/8  Cleaning and star schema load'
\i 07_Data_Cleaning_Script.sql
\echo '5/8  Data validation (all PASS expected)'
\i 08_Data_Validation_Script.sql
\echo '6/8  Database validation (all PASS expected)'
\i 13_Database_Validation.sql
\echo '7/8  RFM segmentation'
\i 17_RFM_Analysis.sql
\echo '8/8  Headline KPIs'
SELECT ROUND(SUM(line_revenue) FILTER (WHERE transaction_type = 'Sale'), 2) AS total_revenue,
       COUNT(DISTINCT invoice_no) FILTER (WHERE transaction_type = 'Sale')  AS orders
FROM dw.fact_sales;
\echo 'Done. Expected: total_revenue 10247219.32, orders 19773.'
