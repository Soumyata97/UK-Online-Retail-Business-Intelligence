/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 08_Data_Validation_Script.sql
   Purpose   : Validate the CLEANING results (raw -> clean -> fact reconciliation).
               Every check returns one row with expected value, actual value and
               PASS / FAIL. A healthy load returns PASS on every row.
   Run order : 4th  (after 07_Data_Cleaning_Script.sql)
   Next step : 13_Database_Validation.sql

   Expected values come from the UCI dataset documentation (541,909 lines) and
   from deterministic rules (e.g. clean rows = raw rows - duplicates). Counts that
   depend on the cleaning rules were produced by running this project's scripts on
   PostgreSQL 16.15 and are recorded in Testing/26_Data_Validation_Test_Cases.xlsx.
   ============================================================================= */

WITH checks AS (

    -- V01 raw row count matches the published dataset size
    SELECT 'V01' AS check_id, 'Raw row count equals published 541,909' AS check_name,
           '541909' AS expected, (SELECT COUNT(*) FROM staging.raw_online_retail)::text AS actual

    UNION ALL
    -- V02 raw has 4,372 distinct non-blank CustomerIDs (published profile)
    SELECT 'V02', 'Distinct CustomerIDs in raw = 4,372', '4372',
           (SELECT COUNT(DISTINCT customer_id) FROM staging.raw_online_retail
             WHERE NULLIF(TRIM(customer_id),'') IS NOT NULL)::text

    UNION ALL
    -- V03 clean rows = raw rows - exact duplicates
    SELECT 'V03', 'Clean rows = raw rows - exact duplicates',
           ((SELECT COUNT(*) FROM staging.raw_online_retail) -
            (SELECT row_count FROM staging.cleaning_log WHERE step_no = 2))::text,
           (SELECT COUNT(*) FROM staging.clean_online_retail)::text

    UNION ALL
    -- V04 no exact duplicates remain in the cleaned table
    SELECT 'V04', 'No exact duplicate lines remain in clean table', '0',
           (SELECT COUNT(*) FROM (
                SELECT 1 FROM staging.clean_online_retail c
                JOIN staging.raw_online_retail r USING (source_row_id)
                GROUP BY r.invoice_no, r.stock_code, r.description, r.quantity,
                         r.invoice_date, r.unit_price, r.customer_id, r.country
                HAVING COUNT(*) > 1) x)::text

    UNION ALL
    -- V05 every raw row is either in clean or is a counted duplicate
    SELECT 'V05', 'Raw rows not in clean = logged duplicates',
           (SELECT row_count FROM staging.cleaning_log WHERE step_no = 2)::text,
           (SELECT COUNT(*) FROM staging.raw_online_retail r
             LEFT JOIN staging.clean_online_retail c USING (source_row_id)
             WHERE c.source_row_id IS NULL)::text

    UNION ALL
    -- V06 transaction types add up to the clean row count
    SELECT 'V06', 'Sum of transaction types = clean rows',
           (SELECT COUNT(*) FROM staging.clean_online_retail)::text,
           (SELECT SUM(row_count) FROM staging.cleaning_log WHERE step_no BETWEEN 4 AND 9)::text

    UNION ALL
    -- V07 every cancellation invoice starts with C and has negative quantity
    SELECT 'V07', 'Cancellation lines with quantity >= 0', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail
             WHERE transaction_type = 'Cancellation' AND quantity >= 0)::text

    UNION ALL
    -- V08 all Sale lines have positive quantity and positive price
    SELECT 'V08', 'Sale lines with quantity <= 0 or price <= 0', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail
             WHERE transaction_type = 'Sale' AND (quantity <= 0 OR unit_price <= 0))::text

    UNION ALL
    -- V09 negative prices only exist on Adjustment (A) invoices
    SELECT 'V09', 'Negative prices outside Adjustment invoices', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail
             WHERE unit_price < 0 AND transaction_type <> 'Adjustment')::text

    UNION ALL
    -- V10 no customer identity was invented: NULL CustomerIDs in raw stay NULL
    SELECT 'V10', 'Clean CustomerIDs that were blank in raw', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail c
             JOIN staging.raw_online_retail r USING (source_row_id)
             WHERE NULLIF(TRIM(r.customer_id),'') IS NULL AND c.customer_id IS NOT NULL)::text

    UNION ALL
    -- V11 line revenue = quantity x unit price on every line
    SELECT 'V11', 'Lines where line_revenue <> quantity * unit_price', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail
             WHERE line_revenue <> quantity * unit_price)::text

    UNION ALL
    -- V12 invoice dates inside the documented period
    SELECT 'V12', 'Invoice dates outside 2010-12-01..2011-12-09', '0',
           (SELECT COUNT(*) FROM staging.clean_online_retail
             WHERE invoice_date NOT BETWEEN DATE '2010-12-01' AND DATE '2011-12-09')::text

    UNION ALL
    -- V13 fact row count = clean row count
    SELECT 'V13', 'fact_sales rows = clean rows',
           (SELECT COUNT(*) FROM staging.clean_online_retail)::text,
           (SELECT COUNT(*) FROM dw.fact_sales)::text

    UNION ALL
    -- V14 fact revenue = clean revenue (no rows lost or duplicated by joins)
    SELECT 'V14', 'SUM(line_revenue) fact = clean',
           (SELECT SUM(line_revenue) FROM staging.clean_online_retail)::text,
           (SELECT SUM(line_revenue) FROM dw.fact_sales)::text

    UNION ALL
    -- V15 Sale revenue matches between clean and fact
    SELECT 'V15', 'Total Revenue (Sale lines) fact = clean',
           (SELECT SUM(line_revenue) FROM staging.clean_online_retail WHERE transaction_type='Sale')::text,
           (SELECT SUM(line_revenue) FROM dw.fact_sales WHERE transaction_type='Sale')::text

    UNION ALL
    -- V16 lines without CustomerID are mapped to the Unknown member only
    SELECT 'V16', 'Fact lines without CustomerID not on customer_key 0', '0',
           (SELECT COUNT(*) FROM dw.fact_sales
             WHERE has_customer_id = FALSE AND customer_key <> 0)::text

    UNION ALL
    -- V17 known customers in fact = distinct CustomerIDs in clean
    SELECT 'V17', 'Distinct known customers fact = clean',
           (SELECT COUNT(DISTINCT customer_id) FROM staging.clean_online_retail)::text,
           (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales WHERE customer_key <> 0)::text

    UNION ALL
    -- V18 invoices preserved
    SELECT 'V18', 'Distinct invoices fact = raw',
           (SELECT COUNT(DISTINCT TRIM(invoice_no)) FROM staging.raw_online_retail)::text,
           (SELECT COUNT(DISTINCT invoice_no) FROM dw.fact_sales)::text
)
SELECT check_id, check_name, expected, actual,
       CASE WHEN expected = actual THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_id;
