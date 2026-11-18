/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 07_Data_Cleaning_Script.sql
   Purpose   : PART A - clean and classify the raw data into staging.clean_online_retail
               PART B - load the star schema (dimensions + fact_sales)
   Run order : 3rd  (after 10_Database_Schema.sql, the CSV import, and 11_Table_Creation.sql)
   Next step : 08_Data_Validation_Script.sql

   The full reasoning for every rule is in Documentation/06_Data_Cleaning_Methodology.docx.
   Summary of the rules implemented here:

   R1  Preserve source   : staging.raw_online_retail is never modified.
   R2  Typing            : text -> INTEGER / TIMESTAMP / NUMERIC(10,3). Exact numeric
                           types are used for money so totals never drift (no FLOAT).
   R3  Trimming          : leading/trailing spaces removed from description, stock code,
                           invoice number and country.
   R4  Stock code case   : stock codes are upper-cased. 112 codes appear in both cases
                           (e.g. 15056BL / 15056bl) with the same description, so they
                           are the same item.
   R5  Exact duplicates  : a line is an exact duplicate when ALL 8 original columns are
                           identical to an earlier line. The first occurrence (lowest
                           source_row_id) is kept; later copies are excluded from the
                           cleaned table and counted in the cleaning log.
   R6  Missing CustomerID: lines are KEPT (they are real sales). They count towards
                           revenue, product and country analysis, but are excluded from
                           customer-level metrics and RFM. No identity is invented.
   R7  Missing description: lines are KEPT with description NULL. The product dimension
                           takes its description from other lines of the same stock code.
   R8  Classification    : every line receives exactly one transaction_type, evaluated
                           in this order:
          1. 'Cancellation'     invoice_no starts with 'C' (UCI documentation)
          2. 'Adjustment'       invoice_no starts with 'A' (bad-debt adjustments)
          3. 'Non-Product'      stock code is a service code (postage, fees, manual,
                                discount, samples, gift vouchers, bad debt)
          4. 'Stock Adjustment' quantity <= 0 on a non-cancellation invoice
                                (price is 0 and there is no customer: stock write-offs)
          5. 'Zero Price'       unit_price = 0 with quantity > 0 (free / unpriced lines)
          6. 'Sale'             everything else (quantity > 0, unit_price > 0, merchandise)
   R9  Negative quantities: NOT removed. Cancellation lines stay (type 1) and are used
                           for Net Revenue. Non-cancellation negatives are stock
                           adjustments (type 4) and carry zero value.
   R10 Invalid prices    : negative prices only occur on 'A' bad-debt invoices (type 2).
                           Zero prices are kept and labelled (type 4 or 5); they add 0 revenue.
   R11 Outliers          : NOT removed. The two largest orders (581483 and 541431) were
                           cancelled minutes later by C581484 and C541433; Net Revenue
                           nets them off. They are flagged in the data quality report.
   ============================================================================= */

-- ============================================================================
-- PART A. CLEANING
-- ============================================================================

-- Make the script re-runnable: empty every table it loads. The RFM table depends on
-- dim_customer, so it is dropped here; re-run 17_RFM_Analysis.sql afterwards.
DROP TABLE IF EXISTS dw.rfm_customer;
TRUNCATE staging.cleaning_log;
TRUNCATE dw.fact_sales, dw.dim_customer, dw.dim_product, dw.dim_country, dw.dim_date RESTART IDENTITY;
TRUNCATE staging.clean_online_retail;

-- Step 1: raw row count
INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 1, 'Raw rows imported', 'R1 source preserved unchanged', COUNT(*)
FROM staging.raw_online_retail;

-- Step 2: exact duplicates (all 8 original columns identical)
INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 2, 'Exact duplicate lines excluded', 'R5 keep first occurrence of identical lines', COUNT(*)
FROM (
    SELECT ROW_NUMBER() OVER (
             PARTITION BY invoice_no, stock_code, description, quantity,
                          invoice_date, unit_price, customer_id, country
             ORDER BY source_row_id) AS rn
    FROM staging.raw_online_retail
) d
WHERE rn > 1;

-- Step 3: build the cleaned, typed and classified table
INSERT INTO staging.clean_online_retail (
    source_row_id, invoice_no, stock_code, description, quantity,
    invoice_datetime, invoice_date, unit_price, customer_id, country,
    line_revenue, transaction_type, is_product, is_cancellation, has_customer_id)
WITH dedup AS (
    SELECT r.*,
           ROW_NUMBER() OVER (
             PARTITION BY invoice_no, stock_code, description, quantity,
                          invoice_date, unit_price, customer_id, country
             ORDER BY source_row_id) AS rn
    FROM staging.raw_online_retail r
),
typed AS (
    SELECT source_row_id,
           TRIM(invoice_no)                                   AS invoice_no,
           UPPER(TRIM(stock_code))                            AS stock_code,
           NULLIF(TRIM(description), '')                      AS description,
           CAST(TRIM(quantity) AS INTEGER)                    AS quantity,
           CAST(TRIM(invoice_date) AS TIMESTAMP)              AS invoice_datetime,
           CAST(TRIM(unit_price) AS NUMERIC(10,3))            AS unit_price,
           CAST(NULLIF(TRIM(customer_id), '') AS INTEGER)     AS customer_id,
           TRIM(country)                                      AS country
    FROM dedup
    WHERE rn = 1
),
flagged AS (
    SELECT t.*,
           (t.stock_code IN ('POST','DOT','C2','M','D','S','BANK CHARGES',
                             'AMAZONFEE','CRUK','B')
            OR t.stock_code LIKE 'GIFT\_0001\_%')              AS is_service_code
    FROM typed t
)
SELECT source_row_id,
       invoice_no,
       stock_code,
       description,
       quantity,
       invoice_datetime,
       CAST(invoice_datetime AS DATE)                         AS invoice_date,
       unit_price,
       customer_id,
       country,
       quantity * unit_price                                  AS line_revenue,
       CASE
           WHEN invoice_no LIKE 'C%'  THEN 'Cancellation'
           WHEN invoice_no LIKE 'A%'  THEN 'Adjustment'
           WHEN is_service_code       THEN 'Non-Product'
           WHEN quantity <= 0         THEN 'Stock Adjustment'
           WHEN unit_price = 0        THEN 'Zero Price'
           ELSE 'Sale'
       END                                                    AS transaction_type,
       NOT is_service_code                                    AS is_product,
       invoice_no LIKE 'C%'                                   AS is_cancellation,
       customer_id IS NOT NULL                                AS has_customer_id
FROM flagged;

INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 3, 'Rows in cleaned table', 'R2-R4 typed, trimmed, stock code upper-cased', COUNT(*)
FROM staging.clean_online_retail;

-- Steps 4-9: rows per transaction type (these add up to step 3)
INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 3 + ROW_NUMBER() OVER (ORDER BY ord),
       'Classified as ' || t.transaction_type,
       'R8 transaction classification',
       COALESCE(c.n, 0)
FROM (VALUES (1,'Sale'),(2,'Cancellation'),(3,'Non-Product'),
             (4,'Stock Adjustment'),(5,'Zero Price'),(6,'Adjustment')) AS t(ord, transaction_type)
LEFT JOIN (SELECT transaction_type, COUNT(*) AS n
           FROM staging.clean_online_retail GROUP BY transaction_type) c
       ON c.transaction_type = t.transaction_type;

-- Step 10: lines without CustomerID (kept, see R6)
INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 10, 'Cleaned lines without CustomerID (kept)', 'R6 kept; excluded from customer metrics', COUNT(*)
FROM staging.clean_online_retail WHERE NOT has_customer_id;

-- Step 11: lines without description (kept, see R7)
INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
SELECT 11, 'Cleaned lines without description (kept)', 'R7 kept; product description taken from dimension', COUNT(*)
FROM staging.clean_online_retail WHERE description IS NULL;

-- ============================================================================
-- PART B. LOAD THE STAR SCHEMA
-- ============================================================================

-- B1. dim_date: every day of 2010 and 2011 (full years are needed for time intelligence)
INSERT INTO dw.dim_date (
    date_key, full_date, day_of_month, day_name, day_of_week_iso, is_weekend,
    week_start_date, iso_week, month_number, month_name, month_short,
    quarter_number, quarter_label, year_number, year_month, year_month_key, is_in_data_range)
SELECT CAST(TO_CHAR(d, 'YYYYMMDD') AS INTEGER),
       d::date,
       EXTRACT(DAY FROM d)::smallint,
       TRIM(TO_CHAR(d, 'Day')),
       EXTRACT(ISODOW FROM d)::smallint,
       EXTRACT(ISODOW FROM d) IN (6, 7),
       DATE_TRUNC('week', d)::date,
       EXTRACT(WEEK FROM d)::smallint,
       EXTRACT(MONTH FROM d)::smallint,
       TRIM(TO_CHAR(d, 'Month')),
       TO_CHAR(d, 'Mon'),
       EXTRACT(QUARTER FROM d)::smallint,
       'Q' || EXTRACT(QUARTER FROM d)::text,
       EXTRACT(YEAR FROM d)::smallint,
       TO_CHAR(d, 'YYYY-MM'),
       CAST(TO_CHAR(d, 'YYYYMM') AS INTEGER),
       d::date BETWEEN DATE '2010-12-01' AND DATE '2011-12-09'
FROM generate_series(DATE '2010-01-01', DATE '2011-12-31', INTERVAL '1 day') AS g(d);

-- B2. dim_country
INSERT INTO dw.dim_country (country_name, map_country_name, market, is_mappable)
SELECT country,
       CASE country
            WHEN 'EIRE'               THEN 'Ireland'
            WHEN 'RSA'                THEN 'South Africa'
            WHEN 'USA'                THEN 'United States'
            WHEN 'Unspecified'        THEN NULL
            WHEN 'European Community' THEN NULL
            ELSE country
       END,
       CASE WHEN country = 'United Kingdom' THEN 'United Kingdom' ELSE 'International' END,
       country NOT IN ('Unspecified', 'European Community')
FROM (SELECT DISTINCT country FROM staging.clean_online_retail) c
ORDER BY country COLLATE "C";

-- B3. dim_product: one row per stock code.
--     Description = most frequent description on priced lines (unit_price > 0),
--     then on any line; ties broken alphabetically (COLLATE "C" = same result on
--     every operating system). Stock codes that never have a description get a label.
INSERT INTO dw.dim_product (stock_code, description, description_variants, item_type, is_product)
WITH desc_counts AS (
    SELECT stock_code, description,
           COUNT(*) FILTER (WHERE unit_price > 0) AS n_priced,
           COUNT(*)                               AS n_all
    FROM staging.clean_online_retail
    WHERE description IS NOT NULL
    GROUP BY stock_code, description
),
ranked AS (
    SELECT stock_code, description,
           ROW_NUMBER() OVER (PARTITION BY stock_code
                              ORDER BY n_priced DESC, n_all DESC, description COLLATE "C") AS rn,
           COUNT(*)     OVER (PARTITION BY stock_code) AS variants
    FROM desc_counts
),
codes AS (
    SELECT stock_code, BOOL_AND(is_product) AS is_product
    FROM staging.clean_online_retail
    GROUP BY stock_code
)
SELECT c.stock_code,
       COALESCE(r.description, 'NO DESCRIPTION IN SOURCE'),
       COALESCE(r.variants, 0),
       CASE
            WHEN c.stock_code IN ('POST','DOT','C2')                 THEN 'Postage & Carriage'
            WHEN c.stock_code IN ('BANK CHARGES','AMAZONFEE','CRUK') THEN 'Fees & Commission'
            WHEN c.stock_code = 'M'                                  THEN 'Manual Adjustment'
            WHEN c.stock_code = 'D'                                  THEN 'Discount'
            WHEN c.stock_code = 'S'                                  THEN 'Samples'
            WHEN c.stock_code = 'B'                                  THEN 'Bad Debt Adjustment'
            WHEN c.stock_code LIKE 'GIFT\_0001\_%'                   THEN 'Gift Voucher'
            ELSE 'Merchandise'
       END,
       c.is_product
FROM codes c
LEFT JOIN ranked r ON r.stock_code = c.stock_code AND r.rn = 1
ORDER BY c.stock_code COLLATE "C";

-- B4. dim_customer: "Unknown" member (key 0) + one row per CustomerID
INSERT INTO dw.dim_customer (customer_key, customer_id, customer_label, primary_country, is_known_customer)
VALUES (0, NULL, 'Unknown (no CustomerID)', NULL, FALSE);

INSERT INTO dw.dim_customer (customer_key, customer_id, customer_label, primary_country, is_known_customer)
WITH country_rank AS (
    SELECT customer_id, country,
           ROW_NUMBER() OVER (PARTITION BY customer_id
                              ORDER BY COUNT(*) DESC, country COLLATE "C") AS rn
    FROM staging.clean_online_retail
    WHERE customer_id IS NOT NULL
    GROUP BY customer_id, country
)
SELECT ROW_NUMBER() OVER (ORDER BY customer_id)::int,
       customer_id,
       'Customer ' || customer_id::text,
       country,
       TRUE
FROM country_rank
WHERE rn = 1;

-- B5. fact_sales
INSERT INTO dw.fact_sales (
    source_row_id, invoice_no, date_key, product_key, customer_key, country_key,
    invoice_datetime, quantity, unit_price, line_revenue, transaction_type,
    cancellation_status, is_product, has_customer_id)
SELECT c.source_row_id,
       c.invoice_no,
       CAST(TO_CHAR(c.invoice_date, 'YYYYMMDD') AS INTEGER),
       p.product_key,
       COALESCE(cu.customer_key, 0),
       co.country_key,
       c.invoice_datetime,
       c.quantity,
       c.unit_price,
       c.line_revenue,
       c.transaction_type,
       CASE WHEN c.is_cancellation THEN 'Cancelled' ELSE 'Not Cancelled' END,
       c.is_product,
       c.has_customer_id
FROM staging.clean_online_retail c
JOIN dw.dim_product  p  ON p.stock_code   = c.stock_code
JOIN dw.dim_country  co ON co.country_name = c.country
LEFT JOIN dw.dim_customer cu ON cu.customer_id = c.customer_id;

INSERT INTO staging.cleaning_log (step_no, step_name, rule_applied, row_count)
VALUES (12, 'dw.dim_date rows',     'calendar 2010-01-01 to 2011-12-31', (SELECT COUNT(*) FROM dw.dim_date)),
       (13, 'dw.dim_country rows',  'distinct countries',                (SELECT COUNT(*) FROM dw.dim_country)),
       (14, 'dw.dim_product rows',  'distinct cleaned stock codes',      (SELECT COUNT(*) FROM dw.dim_product)),
       (15, 'dw.dim_customer rows', 'distinct CustomerIDs + Unknown member', (SELECT COUNT(*) FROM dw.dim_customer)),
       (16, 'dw.fact_sales rows',   'must equal step 3',                 (SELECT COUNT(*) FROM dw.fact_sales));

ANALYZE staging.clean_online_retail;
ANALYZE dw.fact_sales;

-- Show the cleaning log (record counts before/after every step)
SELECT step_no, step_name, rule_applied, row_count
FROM staging.cleaning_log
ORDER BY step_no;
