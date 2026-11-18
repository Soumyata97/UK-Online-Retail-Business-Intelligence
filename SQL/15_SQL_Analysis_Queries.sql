/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 15_SQL_Analysis_Queries.sql
   Purpose   : 33 business analysis queries on the dw star schema.
   Run order : 6th  (after 13_Database_Validation.sql). Queries are independent:
               highlight ONE query in pgAdmin and press F5 (Execute) to run it.
   Status    : Executed by the author on PostgreSQL 16.15 against the full dataset.
               Reference outputs: Analysis_Outputs/sql_results/Qxx.csv
               Not yet executed on your PostgreSQL 18 installation.

   SHARED BUSINESS DEFINITIONS (identical in SQL, Power BI and the reports)
   -------------------------------------------------------------------------
   Sale line            transaction_type = 'Sale'  (merchandise, qty > 0, price > 0,
                        not a cancellation invoice)
   Total Revenue        SUM(line_revenue) of Sale lines  = gross product sales (GBP)
   Product Cancellations SUM(line_revenue) of Cancellation lines where is_product
                        (negative number)
   Net Revenue          Total Revenue + Product Cancellations
   Gross Positive Sales SUM(line_revenue) of Sale + Non-Product lines with
                        line_revenue > 0 on non-cancelled invoices (includes postage)
   Order                a distinct invoice_no that contains at least one Sale line
   Average Order Value  Total Revenue / Orders
   Customer metrics     only lines with a CustomerID (customer_key <> 0)

   Each query block has: Query ID, Business question, Explanation, Output columns,
   Business relevance, Learning objective. The "-- @@QUERY" marker lines are used
   by the project's test harness to run each query separately; leave them in.
   ============================================================================= */


/* =============================================================================
   A. REVENUE ANALYSIS
   ============================================================================= */

-- @@QUERY Q01
/* Query ID          : Q01
   Business question : What are the headline sales KPIs for the whole period?
   Explanation       : Conditional aggregation (FILTER) calculates every KPI in one
                       pass over fact_sales. Orders and customers use DISTINCT counts.
   Output columns    : total_revenue, gross_positive_sales, product_cancellations,
                       net_revenue, orders, customers, units_sold, average_order_value
   Business relevance: The KPI cards on the Executive Overview page.
   Learning objective: Aggregate functions, FILTER (WHERE ...), COUNT(DISTINCT), ROUND. */
SELECT
    ROUND(SUM(line_revenue) FILTER (WHERE transaction_type = 'Sale'), 2)              AS total_revenue,
    ROUND(SUM(line_revenue) FILTER (WHERE cancellation_status = 'Not Cancelled'
                                      AND transaction_type IN ('Sale','Non-Product')
                                      AND line_revenue > 0), 2)                         AS gross_positive_sales,
    ROUND(SUM(line_revenue) FILTER (WHERE transaction_type = 'Cancellation'
                                      AND is_product), 2)                               AS product_cancellations,
    ROUND(SUM(line_revenue) FILTER (WHERE transaction_type = 'Sale'
                                       OR (transaction_type = 'Cancellation' AND is_product)), 2) AS net_revenue,
    COUNT(DISTINCT invoice_no) FILTER (WHERE transaction_type = 'Sale')                 AS orders,
    COUNT(DISTINCT customer_key) FILTER (WHERE transaction_type = 'Sale'
                                           AND customer_key <> 0)                       AS customers,
    SUM(quantity) FILTER (WHERE transaction_type = 'Sale')                              AS units_sold,
    ROUND(SUM(line_revenue) FILTER (WHERE transaction_type = 'Sale')
          / COUNT(DISTINCT invoice_no) FILTER (WHERE transaction_type = 'Sale'), 2)     AS average_order_value
FROM dw.fact_sales;


-- @@QUERY Q02
/* Query ID          : Q02
   Business question : How does revenue change month by month?
   Explanation       : INNER JOIN to dim_date gives the calendar month; GROUP BY month.
                       December 2011 contains only 9 trading days (data ends 2011-12-09).
   Output columns    : year_month, total_revenue, product_cancellations, net_revenue, orders
   Business relevance: Monthly trend line on the Executive and Trends pages.
   Learning objective: INNER JOIN fact -> dimension, GROUP BY, conditional SUM. */
SELECT d.year_month,
       ROUND(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale'), 2)                       AS total_revenue,
       ROUND(COALESCE(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation'
                                                    AND f.is_product), 0), 2)                       AS product_cancellations,
       ROUND(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale'
                                            OR (f.transaction_type = 'Cancellation' AND f.is_product)), 2) AS net_revenue,
       COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale')                        AS orders
FROM dw.fact_sales f
INNER JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.year_month, d.year_month_key
ORDER BY d.year_month_key;


-- @@QUERY Q03
/* Query ID          : Q03
   Business question : What is the daily revenue and how many orders are placed per day?
   Explanation       : Groups Sale lines by calendar date. Days with no trading do not
                       appear (there are no Saturday transactions in this dataset).
   Output columns    : full_date, day_name, total_revenue, orders
   Business relevance: Daily trend and identification of peak trading days.
   Learning objective: Grouping at a finer grain; using dimension attributes. */
SELECT d.full_date,
       d.day_name,
       ROUND(SUM(f.line_revenue), 2)  AS total_revenue,
       COUNT(DISTINCT f.invoice_no)   AS orders
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.transaction_type = 'Sale'
GROUP BY d.full_date, d.day_name
ORDER BY d.full_date;


-- @@QUERY Q04
/* Query ID          : Q04
   Business question : What is the revenue per quarter?
   Explanation       : Groups by year and quarter. Q4 2010 = December 2010 only and
                       Q4 2011 = 1 Oct - 9 Dec 2011, so neither is a complete quarter.
   Output columns    : year_number, quarter_label, months_with_data, total_revenue, orders, is_complete_quarter
   Business relevance: Quarterly reporting; flags partial periods so they are not misread.
   Learning objective: COUNT(DISTINCT) on a dimension attribute, CASE WHEN for flags. */
SELECT d.year_number,
       d.quarter_label,
       COUNT(DISTINCT d.month_number)            AS months_with_data,
       ROUND(SUM(f.line_revenue), 2)             AS total_revenue,
       COUNT(DISTINCT f.invoice_no)              AS orders,
       CASE WHEN (d.year_number = 2010 AND d.quarter_number = 4)
              OR (d.year_number = 2011 AND d.quarter_number = 4)
            THEN 'No - partial quarter' ELSE 'Yes' END AS is_complete_quarter
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.transaction_type = 'Sale'
GROUP BY d.year_number, d.quarter_number, d.quarter_label
ORDER BY d.year_number, d.quarter_number;


-- @@QUERY Q05
/* Query ID          : Q05
   Business question : What is the month-over-month revenue growth?
   Explanation       : A CTE builds monthly revenue; LAG() reads the previous month's
                       value on the same result row; NULLIF avoids division by zero.
   Output columns    : year_month, total_revenue, previous_month_revenue, mom_change, mom_growth_pct
   Business relevance: Shows acceleration or slowdown in sales.
   Learning objective: CTE, window function LAG, safe percentage calculation. */
WITH monthly AS (
    SELECT d.year_month_key, d.year_month, SUM(f.line_revenue) AS total_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.transaction_type = 'Sale'
    GROUP BY d.year_month_key, d.year_month
)
SELECT year_month,
       ROUND(total_revenue, 2)                                              AS total_revenue,
       ROUND(LAG(total_revenue) OVER (ORDER BY year_month_key), 2)          AS previous_month_revenue,
       ROUND(total_revenue - LAG(total_revenue) OVER (ORDER BY year_month_key), 2) AS mom_change,
       ROUND(100.0 * (total_revenue - LAG(total_revenue) OVER (ORDER BY year_month_key))
             / NULLIF(LAG(total_revenue) OVER (ORDER BY year_month_key), 0), 1)   AS mom_growth_pct
FROM monthly
ORDER BY year_month_key;


-- @@QUERY Q06
/* Query ID          : Q06
   Business question : What is the cumulative (running) revenue through the period?
   Explanation       : SUM() OVER (ORDER BY ...) with a ROWS frame adds each month to
                       all previous months.
   Output columns    : year_month, total_revenue, running_total_revenue, running_pct_of_period
   Business relevance: Tracks progress towards the period total.
   Learning objective: Running totals with window frames. */
WITH monthly AS (
    SELECT d.year_month_key, d.year_month, SUM(f.line_revenue) AS total_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_date d ON d.date_key = f.date_key
    WHERE f.transaction_type = 'Sale'
    GROUP BY d.year_month_key, d.year_month
)
SELECT year_month,
       ROUND(total_revenue, 2) AS total_revenue,
       ROUND(SUM(total_revenue) OVER (ORDER BY year_month_key
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW), 2) AS running_total_revenue,
       ROUND(100.0 * SUM(total_revenue) OVER (ORDER BY year_month_key
                                      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(total_revenue) OVER (), 1)                                              AS running_pct_of_period
FROM monthly
ORDER BY year_month_key;


-- @@QUERY Q07
/* Query ID          : Q07
   Business question : Which days of the week generate the most revenue?
   Explanation       : Groups Sale lines by ISO weekday. Also counts trading days so
                       average revenue per trading day can be compared fairly.
   Output columns    : day_of_week_iso, day_name, trading_days, total_revenue, avg_revenue_per_trading_day
   Business relevance: Weekly seasonality; staffing and campaign timing.
   Learning objective: Normalising a total by a count to compare unequal groups. */
SELECT d.day_of_week_iso,
       d.day_name,
       COUNT(DISTINCT d.full_date)                                      AS trading_days,
       ROUND(SUM(f.line_revenue), 2)                                    AS total_revenue,
       ROUND(SUM(f.line_revenue) / COUNT(DISTINCT d.full_date), 2)      AS avg_revenue_per_trading_day
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.transaction_type = 'Sale'
GROUP BY d.day_of_week_iso, d.day_name
ORDER BY d.day_of_week_iso;


-- @@QUERY Q08
/* Query ID          : Q08
   Business question : At what time of day are orders placed?
   Explanation       : EXTRACT(HOUR ...) from the invoice timestamp.
   Output columns    : hour_of_day, orders, total_revenue, revenue_share_pct
   Business relevance: Intraday pattern for operations and email timing.
   Learning objective: Date/time functions; share of total with SUM() OVER (). */
SELECT EXTRACT(HOUR FROM invoice_datetime)::int                               AS hour_of_day,
       COUNT(DISTINCT invoice_no)                                             AS orders,
       ROUND(SUM(line_revenue), 2)                                            AS total_revenue,
       ROUND(100.0 * SUM(line_revenue) / SUM(SUM(line_revenue)) OVER (), 1)   AS revenue_share_pct
FROM dw.fact_sales
WHERE transaction_type = 'Sale'
GROUP BY EXTRACT(HOUR FROM invoice_datetime)
ORDER BY hour_of_day;


/* =============================================================================
   B. PRODUCT ANALYSIS
   (No product categories exist in the source; none are invented.)
   ============================================================================= */

-- @@QUERY Q09
/* Query ID          : Q09
   Business question : Which 10 products generate the highest revenue?
   Explanation       : Net revenue per product (Sale lines + that product's cancellation
                       lines), ranked with RANK() (ties share a rank, next rank skipped).
                       Net is used because two single orders (581483 and 541431) were
                       cancelled within minutes; ranked on gross sales they would wrongly
                       appear at positions 2 and 6. Gross sales are shown for comparison.
   Output columns    : revenue_rank, stock_code, description, net_revenue, gross_sales,
                       cancelled_value, orders
   Business relevance: Identifies the products that genuinely matter to the business.
   Learning objective: RANK() window function, conditional aggregation, JOIN to a dimension. */
WITH product_revenue AS (
    SELECT p.stock_code, p.description,
           SUM(f.line_revenue)                                                   AS net_revenue,
           SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale')        AS gross_sales,
           COALESCE(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation'), 0) AS cancelled_value,
           COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale') AS orders
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.transaction_type = 'Sale'
       OR (f.transaction_type = 'Cancellation' AND f.is_product)
    GROUP BY p.stock_code, p.description
),
ranked AS (
    SELECT *, RANK() OVER (ORDER BY net_revenue DESC) AS revenue_rank
    FROM product_revenue
)
SELECT revenue_rank, stock_code, description,
       ROUND(net_revenue, 2)     AS net_revenue,
       ROUND(gross_sales, 2)     AS gross_sales,
       ROUND(cancelled_value, 2) AS cancelled_value,
       orders
FROM ranked
WHERE revenue_rank <= 10
ORDER BY revenue_rank, stock_code;


-- @@QUERY Q10
/* Query ID          : Q10
   Business question : Which 10 products sell the highest quantities?
   Explanation       : Net units per product (units sold minus units cancelled) ranked
                       with DENSE_RANK() (ties share a rank, no gaps). Compare with Q09:
                       volume leaders are not always revenue leaders.
   Output columns    : quantity_rank, stock_code, description, net_units, gross_units,
                       net_revenue, avg_selling_price
   Business relevance: Volume drivers for stock planning and supplier negotiation.
   Learning objective: DENSE_RANK() versus RANK(). */
WITH product_qty AS (
    SELECT p.stock_code, p.description,
           SUM(f.quantity)                                                AS net_units,
           SUM(f.quantity) FILTER (WHERE f.transaction_type = 'Sale')     AS gross_units,
           SUM(f.line_revenue)                                            AS net_revenue,
           SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale') AS gross_sales
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.transaction_type = 'Sale'
       OR (f.transaction_type = 'Cancellation' AND f.is_product)
    GROUP BY p.stock_code, p.description
)
SELECT quantity_rank, stock_code, description, net_units, gross_units,
       ROUND(net_revenue, 2)               AS net_revenue,
       ROUND(gross_sales / gross_units, 3) AS avg_selling_price
FROM (SELECT *, DENSE_RANK() OVER (ORDER BY net_units DESC) AS quantity_rank FROM product_qty) r
WHERE quantity_rank <= 10
ORDER BY quantity_rank, stock_code;


-- @@QUERY Q11
/* Query ID          : Q11
   Business question : Which 10 products generate the lowest revenue?
   Explanation       : ROW_NUMBER() gives a unique position even when revenue ties
                       (stock_code breaks ties so the result is repeatable).
   Output columns    : bottom_position, stock_code, description, total_revenue, units_sold, orders
   Business relevance: Candidates for range review (low sellers tie up catalogue space).
   Learning objective: ROW_NUMBER() with a deterministic tie-breaker. */
WITH product_revenue AS (
    SELECT p.stock_code, p.description,
           SUM(f.line_revenue) AS total_revenue,
           SUM(f.quantity) AS units_sold,
           COUNT(DISTINCT f.invoice_no) AS orders
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.transaction_type = 'Sale'
    GROUP BY p.stock_code, p.description
)
SELECT bottom_position, stock_code, description, ROUND(total_revenue, 3) AS total_revenue, units_sold, orders
FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY total_revenue ASC, stock_code COLLATE "C") AS bottom_position
      FROM product_revenue) r
WHERE bottom_position <= 10
ORDER BY bottom_position;


-- @@QUERY Q12
/* Query ID          : Q12
   Business question : How concentrated is revenue across products (Pareto analysis)?
   Explanation       : Products sorted from highest to lowest net revenue; a cumulative
                       window SUM shows how many products deliver 80% of net revenue.
                       Only products with positive net revenue are counted.
   Output columns    : products_with_positive_net_revenue, products_for_80pct_revenue,
                       pct_of_products_for_80pct, top_10_products_revenue_share_pct
   Business relevance: Shows whether a small part of the catalogue drives most sales.
   Learning objective: Cumulative window SUM, nested CTEs, scalar summary. */
WITH product_revenue AS (
    SELECT f.product_key, SUM(f.line_revenue) AS net_revenue
    FROM dw.fact_sales f
    WHERE f.transaction_type = 'Sale'
       OR (f.transaction_type = 'Cancellation' AND f.is_product)
    GROUP BY f.product_key
    HAVING SUM(f.line_revenue) > 0
),
cumulative AS (
    SELECT product_key, net_revenue,
           ROW_NUMBER() OVER (ORDER BY net_revenue DESC, product_key) AS pos,
           SUM(net_revenue) OVER (ORDER BY net_revenue DESC, product_key
                                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(net_revenue) OVER () AS cum_share
    FROM product_revenue
)
SELECT COUNT(*)                                                     AS products_with_positive_net_revenue,
       MIN(pos) FILTER (WHERE cum_share >= 0.80)                    AS products_for_80pct_revenue,
       ROUND(100.0 * MIN(pos) FILTER (WHERE cum_share >= 0.80) / COUNT(*), 1) AS pct_of_products_for_80pct,
       ROUND(100.0 * MAX(cum_share) FILTER (WHERE pos = 10), 1)     AS top_10_products_revenue_share_pct
FROM cumulative;


-- @@QUERY Q13
/* Query ID          : Q13
   Business question : What is each product's revenue contribution and overall rank?
   Explanation       : Full product ranking on net revenue with share of total and NTILE(4)
                       quartile (1 = top 25% of products). Top 25 shown; remove the final
                       WHERE to see every product.
   Output columns    : revenue_rank, stock_code, description, net_revenue,
                       revenue_share_pct, cumulative_share_pct, revenue_quartile
   Business relevance: Product contribution table on the Product Performance page.
   Learning objective: Several window functions over the same ordering; NTILE. */
WITH product_revenue AS (
    SELECT p.stock_code, p.description, SUM(f.line_revenue) AS net_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_product p ON p.product_key = f.product_key
    WHERE f.transaction_type = 'Sale'
       OR (f.transaction_type = 'Cancellation' AND f.is_product)
    GROUP BY p.stock_code, p.description
)
SELECT *
FROM (
    SELECT RANK() OVER (ORDER BY net_revenue DESC)                                    AS revenue_rank,
           stock_code, description,
           ROUND(net_revenue, 2)                                                      AS net_revenue,
           ROUND(100.0 * net_revenue / SUM(net_revenue) OVER (), 3)                   AS revenue_share_pct,
           ROUND(100.0 * SUM(net_revenue) OVER (ORDER BY net_revenue DESC, stock_code COLLATE "C"
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                 / SUM(net_revenue) OVER (), 2)                                       AS cumulative_share_pct,
           NTILE(4) OVER (ORDER BY net_revenue DESC, stock_code COLLATE "C")          AS revenue_quartile
    FROM product_revenue
) r
WHERE revenue_rank <= 25
ORDER BY revenue_rank, stock_code;


-- @@QUERY Q14
/* Query ID          : Q14
   Business question : Which products have the highest cancelled value?
   Explanation       : Sums negative cancellation lines per product and compares them
                       with the product's gross sales.
   Output columns    : stock_code, description, cancelled_value, cancelled_units,
                       gross_sales, cancelled_pct_of_sales
   Business relevance: Highlights products that may have quality, pricing or order-entry issues.
   Learning objective: Two conditional aggregates on one grouping; HAVING. */
SELECT p.stock_code, p.description,
       ROUND(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation'), 2) AS cancelled_value,
       -SUM(f.quantity) FILTER (WHERE f.transaction_type = 'Cancellation')            AS cancelled_units,
       ROUND(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale'), 2)         AS gross_sales,
       ROUND(100.0 * -SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation')
             / NULLIF(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale'), 0), 1) AS cancelled_pct_of_sales
FROM dw.fact_sales f
JOIN dw.dim_product p ON p.product_key = f.product_key
WHERE p.is_product
GROUP BY p.stock_code, p.description
HAVING SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation') < 0
ORDER BY cancelled_value ASC
LIMIT 10;


/* =============================================================================
   C. CUSTOMER ANALYSIS (only lines with a CustomerID)
   ============================================================================= */

-- @@QUERY Q15
/* Query ID          : Q15
   Business question : How many unique customers are there, and how much revenue
                       cannot be attributed to a customer?
   Explanation       : LEFT JOIN keeps every Sale line, including those on the
                       Unknown member; CASE splits identified vs unidentified.
   Output columns    : customer_group, customers, orders, total_revenue, revenue_share_pct
   Business relevance: Quantifies the limitation of customer analysis (missing IDs).
   Learning objective: LEFT JOIN, CASE WHEN grouping, share of total. */
SELECT CASE WHEN c.is_known_customer THEN 'Identified customer' ELSE 'No CustomerID' END AS customer_group,
       COUNT(DISTINCT c.customer_id)                                         AS customers,
       COUNT(DISTINCT f.invoice_no)                                          AS orders,
       ROUND(SUM(f.line_revenue), 2)                                         AS total_revenue,
       ROUND(100.0 * SUM(f.line_revenue) / SUM(SUM(f.line_revenue)) OVER (), 1) AS revenue_share_pct
FROM dw.fact_sales f
LEFT JOIN dw.dim_customer c ON c.customer_key = f.customer_key
WHERE f.transaction_type = 'Sale'
GROUP BY CASE WHEN c.is_known_customer THEN 'Identified customer' ELSE 'No CustomerID' END
ORDER BY customer_group;


-- @@QUERY Q16
/* Query ID          : Q16
   Business question : Who are the 10 highest-value customers?
   Explanation       : Net revenue per customer (Sale lines + product cancellations),
                       ranked with RANK(). CustomerIDs are anonymised numbers in the source.
   Output columns    : customer_rank, customer_id, primary_country, orders, net_revenue,
                       share_of_identified_revenue_pct
   Business relevance: Key-account list for retention and account management.
   Learning objective: CTE + RANK(), filtering on a window result in an outer query. */
WITH customer_value AS (
    SELECT c.customer_id, c.primary_country,
           COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale') AS orders,
           SUM(f.line_revenue)                                                     AS net_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_key = f.customer_key
    WHERE c.customer_key <> 0
      AND (f.transaction_type = 'Sale' OR (f.transaction_type = 'Cancellation' AND f.is_product))
    GROUP BY c.customer_id, c.primary_country
)
SELECT customer_rank, customer_id, primary_country, orders,
       ROUND(net_revenue, 2) AS net_revenue,
       ROUND(share_pct, 2)   AS share_of_identified_revenue_pct
FROM (SELECT *, RANK() OVER (ORDER BY net_revenue DESC) AS customer_rank,
             100.0 * net_revenue / SUM(net_revenue) OVER () AS share_pct
      FROM customer_value) r
WHERE customer_rank <= 10
ORDER BY customer_rank;


-- @@QUERY Q17
/* Query ID          : Q17
   Business question : What does a typical customer look like (spend, orders, tenure)?
   Explanation       : A CTE builds one row per customer (first/last purchase, orders,
                       lifetime revenue within the observed period); the outer query
                       summarises with AVG and PERCENTILE_CONT (median).
   Output columns    : customers, avg_customer_revenue, median_customer_revenue,
                       avg_orders_per_customer, median_orders_per_customer, avg_active_days
   Business relevance: Average Customer Spending KPI; medians show the skew.
   Learning objective: Two-level aggregation, PERCENTILE_CONT ... WITHIN GROUP. */
WITH customer_summary AS (
    SELECT f.customer_key,
           MIN(f.invoice_datetime)::date   AS first_purchase_date,
           MAX(f.invoice_datetime)::date   AS last_purchase_date,
           COUNT(DISTINCT f.invoice_no)    AS orders,
           SUM(f.line_revenue)             AS lifetime_revenue
    FROM dw.fact_sales f
    WHERE f.transaction_type = 'Sale' AND f.customer_key <> 0
    GROUP BY f.customer_key
)
SELECT COUNT(*)                                                                    AS customers,
       ROUND(AVG(lifetime_revenue), 2)                                             AS avg_customer_revenue,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY lifetime_revenue) AS NUMERIC), 2) AS median_customer_revenue,
       ROUND(AVG(orders), 2)                                                       AS avg_orders_per_customer,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY orders)                         AS median_orders_per_customer,
       ROUND(AVG(last_purchase_date - first_purchase_date), 1)                     AS avg_active_days
FROM customer_summary;


-- @@QUERY Q18
/* Query ID          : Q18
   Business question : How frequently do customers purchase?
   Explanation       : CASE WHEN buckets each customer's order count; the window SUM
                       turns counts into percentages.
   Output columns    : frequency_band, customers, pct_of_customers, total_revenue, pct_of_revenue
   Business relevance: Purchase-frequency distribution chart on Customer Analytics.
   Learning objective: CASE WHEN bucketing on an aggregated CTE; sort key column. */
WITH customer_orders AS (
    SELECT customer_key, COUNT(DISTINCT invoice_no) AS orders, SUM(line_revenue) AS revenue
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
    GROUP BY customer_key
),
banded AS (
    SELECT CASE WHEN orders = 1 THEN 1 WHEN orders = 2 THEN 2 WHEN orders BETWEEN 3 AND 5 THEN 3
                WHEN orders BETWEEN 6 AND 10 THEN 4 ELSE 5 END AS band_order,
           CASE WHEN orders = 1 THEN '1 order' WHEN orders = 2 THEN '2 orders'
                WHEN orders BETWEEN 3 AND 5 THEN '3-5 orders'
                WHEN orders BETWEEN 6 AND 10 THEN '6-10 orders' ELSE '11+ orders' END AS frequency_band,
           revenue
    FROM customer_orders
)
SELECT frequency_band,
       COUNT(*)                                                         AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)               AS pct_of_customers,
       ROUND(SUM(revenue), 2)                                           AS total_revenue,
       ROUND(100.0 * SUM(revenue) / SUM(SUM(revenue)) OVER (), 1)       AS pct_of_revenue
FROM banded
GROUP BY band_order, frequency_band
ORDER BY band_order;


-- @@QUERY Q19
/* Query ID          : Q19
   Business question : What proportion of customers make repeat purchases?
   Explanation       : HAVING keeps customers with more than one order; the outer query
                       divides by all customers.
   Output columns    : total_customers, repeat_customers, one_time_customers, repeat_customer_rate_pct
   Business relevance: Core retention KPI.
   Learning objective: HAVING versus WHERE; scalar subqueries. */
SELECT (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales
         WHERE transaction_type = 'Sale' AND customer_key <> 0)                AS total_customers,
       COUNT(*)                                                                 AS repeat_customers,
       (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales
         WHERE transaction_type = 'Sale' AND customer_key <> 0) - COUNT(*)     AS one_time_customers,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales
                                  WHERE transaction_type = 'Sale' AND customer_key <> 0), 1) AS repeat_customer_rate_pct
FROM (
    SELECT customer_key
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
    GROUP BY customer_key
    HAVING COUNT(DISTINCT invoice_no) > 1
) repeaters;


-- @@QUERY Q20
/* Query ID          : Q20
   Business question : How many customers spend more than the average customer, and
                       what share of revenue do they generate?
   Explanation       : A subquery in WHERE compares each customer's revenue with the
                       average customer revenue.
   Output columns    : avg_customer_revenue, customers_above_average, pct_of_customers, revenue_share_pct
   Business relevance: Shows the skew of customer value (a few large wholesalers).
   Learning objective: Subquery in WHERE and in SELECT. */
WITH customer_revenue AS (
    SELECT customer_key, SUM(line_revenue) AS revenue
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
    GROUP BY customer_key
)
SELECT ROUND((SELECT AVG(revenue) FROM customer_revenue), 2)                       AS avg_customer_revenue,
       COUNT(*)                                                                    AS customers_above_average,
       ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM customer_revenue), 1)        AS pct_of_customers,
       ROUND(100.0 * SUM(revenue) / (SELECT SUM(revenue) FROM customer_revenue), 1) AS revenue_share_pct
FROM customer_revenue
WHERE revenue > (SELECT AVG(revenue) FROM customer_revenue);


-- @@QUERY Q21
/* Query ID          : Q21
   Business question : For repeat customers, how many days pass between orders?
   Explanation       : One row per customer order (first timestamp of the invoice);
                       LAG() gets the previous order date of the same customer
                       (PARTITION BY customer).
   Output columns    : repeat_customers, order_gaps_measured, avg_days_between_orders, median_days_between_orders
   Business relevance: Typical re-order cycle; basis for reminder campaigns.
   Learning objective: LAG with PARTITION BY; date subtraction. */
WITH orders AS (
    SELECT customer_key, invoice_no, MIN(invoice_datetime)::date AS order_date
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
    GROUP BY customer_key, invoice_no
),
gaps AS (
    SELECT customer_key,
           order_date - LAG(order_date) OVER (PARTITION BY customer_key ORDER BY order_date, invoice_no) AS gap_days
    FROM orders
)
SELECT COUNT(DISTINCT customer_key)                                         AS repeat_customers,
       COUNT(*)                                                             AS order_gaps_measured,
       ROUND(AVG(gap_days), 1)                                              AS avg_days_between_orders,
       PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY gap_days)                AS median_days_between_orders
FROM gaps
WHERE gap_days IS NOT NULL;


-- @@QUERY Q22
/* Query ID          : Q22
   Business question : Each month, how many customers are new and how many are returning?
   Explanation       : First purchase month per customer (CTE); each monthly active
                       customer is "New" if that month is their first month, else "Returning".
                       December 2010 shows every customer as new because no earlier data exists.
   Output columns    : year_month, active_customers, new_customers, returning_customers, returning_pct
   Business relevance: Acquisition versus retention over time.
   Learning objective: Joining a CTE back to detail; DATE_TRUNC. */
WITH first_month AS (
    SELECT customer_key, DATE_TRUNC('month', MIN(invoice_datetime)) AS first_month
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
    GROUP BY customer_key
),
monthly_active AS (
    SELECT DISTINCT customer_key, DATE_TRUNC('month', invoice_datetime) AS activity_month
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale' AND customer_key <> 0
)
SELECT TO_CHAR(m.activity_month, 'YYYY-MM')                                 AS year_month,
       COUNT(*)                                                             AS active_customers,
       COUNT(*) FILTER (WHERE m.activity_month = fm.first_month)            AS new_customers,
       COUNT(*) FILTER (WHERE m.activity_month > fm.first_month)            AS returning_customers,
       ROUND(100.0 * COUNT(*) FILTER (WHERE m.activity_month > fm.first_month) / COUNT(*), 1) AS returning_pct
FROM monthly_active m
JOIN first_month fm ON fm.customer_key = m.customer_key
GROUP BY m.activity_month
ORDER BY m.activity_month;


/* =============================================================================
   D. ORDER ANALYSIS
   ============================================================================= */

-- @@QUERY Q23
/* Query ID          : Q23
   Business question : What is the average order value, and how large is a typical order?
   Explanation       : CTE builds one row per order (lines, units, value); outer query
                       averages them. Median shows the typical order without big-order skew.
   Output columns    : orders, average_order_value, median_order_value,
                       avg_lines_per_order, avg_units_per_order
   Business relevance: AOV and basket size KPIs.
   Learning objective: Order-level CTE, AVG versus median. */
WITH order_summary AS (
    SELECT invoice_no,
           COUNT(*)            AS order_lines,
           SUM(quantity)       AS units,
           SUM(line_revenue)   AS order_value
    FROM dw.fact_sales
    WHERE transaction_type = 'Sale'
    GROUP BY invoice_no
)
SELECT COUNT(*)                                                                      AS orders,
       ROUND(AVG(order_value), 2)                                                    AS average_order_value,
       ROUND(CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY order_value) AS NUMERIC), 2) AS median_order_value,
       ROUND(AVG(order_lines), 1)                                                    AS avg_lines_per_order,
       ROUND(AVG(units), 1)                                                          AS avg_units_per_order
FROM order_summary;


-- @@QUERY Q24
/* Query ID          : Q24
   Business question : How many orders are placed each month and what is the monthly AOV?
   Explanation       : Monthly distinct invoices and revenue divided by orders.
   Output columns    : year_month, orders, total_revenue, average_order_value, active_customers
   Business relevance: Separates growth from more orders versus larger orders.
   Learning objective: Ratio of aggregates per group. */
SELECT d.year_month,
       COUNT(DISTINCT f.invoice_no)                                              AS orders,
       ROUND(SUM(f.line_revenue), 2)                                             AS total_revenue,
       ROUND(SUM(f.line_revenue) / COUNT(DISTINCT f.invoice_no), 2)              AS average_order_value,
       COUNT(DISTINCT f.customer_key) FILTER (WHERE f.customer_key <> 0)         AS active_customers
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
WHERE f.transaction_type = 'Sale'
GROUP BY d.year_month_key, d.year_month
ORDER BY d.year_month_key;


-- @@QUERY Q25
/* Query ID          : Q25
   Business question : How many invoices were cancelled and what is the cancellation rate?
   Explanation       : Invoice-based rate = cancellation invoices / (orders + cancellation
                       invoices). Value-based rate = |product cancellations| / Total Revenue.
                       Cancellation invoices cannot be matched line-by-line to the original
                       orders (the source has no link), so both rates are period-level ratios.
   Output columns    : orders, cancellation_invoices, cancellation_rate_pct,
                       product_cancellation_value, value_cancellation_rate_pct, customers_with_cancellations
   Business relevance: Cancellation KPIs on the Trends & Cancellations page.
   Learning objective: Combining several CTE results with CROSS JOIN. */
WITH o AS (
    SELECT COUNT(DISTINCT invoice_no) AS orders, SUM(line_revenue) AS total_revenue
    FROM dw.fact_sales WHERE transaction_type = 'Sale'
),
c AS (
    SELECT COUNT(DISTINCT invoice_no)                                       AS cancellation_invoices,
           SUM(line_revenue) FILTER (WHERE is_product)                      AS product_cancellation_value,
           COUNT(DISTINCT customer_key) FILTER (WHERE customer_key <> 0)    AS customers_with_cancellations
    FROM dw.fact_sales WHERE transaction_type = 'Cancellation'
)
SELECT o.orders,
       c.cancellation_invoices,
       ROUND(100.0 * c.cancellation_invoices / (o.orders + c.cancellation_invoices), 1) AS cancellation_rate_pct,
       ROUND(c.product_cancellation_value, 2)                                          AS product_cancellation_value,
       ROUND(100.0 * -c.product_cancellation_value / o.total_revenue, 1)               AS value_cancellation_rate_pct,
       c.customers_with_cancellations
FROM o CROSS JOIN c;


-- @@QUERY Q26
/* Query ID          : Q26
   Business question : How do cancellations trend month by month?
   Explanation       : Monthly cancellation invoices and value next to monthly orders.
   Output columns    : year_month, orders, cancellation_invoices, cancellation_rate_pct,
                       product_cancellation_value, value_cancellation_rate_pct
   Business relevance: Detects months with unusual cancellation activity.
   Learning objective: Multiple conditional COUNT(DISTINCT) in one GROUP BY. */
SELECT d.year_month,
       COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale')          AS orders,
       COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Cancellation')  AS cancellation_invoices,
       ROUND(100.0 * COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Cancellation')
             / NULLIF(COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type IN ('Sale','Cancellation')), 0), 1)
                                                                                         AS cancellation_rate_pct,
       ROUND(COALESCE(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation' AND f.is_product), 0), 2)
                                                                                         AS product_cancellation_value,
       ROUND(100.0 * -COALESCE(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation' AND f.is_product), 0)
             / NULLIF(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Sale'), 0), 1) AS value_cancellation_rate_pct
FROM dw.fact_sales f
JOIN dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.year_month_key, d.year_month
ORDER BY d.year_month_key;


-- @@QUERY Q27
/* Query ID          : Q27
   Business question : Which countries have the highest cancellation rates?
   Explanation       : Invoice-based cancellation rate per country, limited with HAVING
                       to countries with at least 50 orders so small samples do not dominate.
   Output columns    : country_name, orders, cancellation_invoices, cancellation_rate_pct, product_cancellation_value
   Business relevance: Market-level service or order-accuracy issues.
   Learning objective: HAVING with an aggregate condition; minimum-sample rule. */
SELECT co.country_name,
       COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale')          AS orders,
       COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Cancellation')  AS cancellation_invoices,
       ROUND(100.0 * COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Cancellation')
             / COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type IN ('Sale','Cancellation')), 1) AS cancellation_rate_pct,
       ROUND(COALESCE(SUM(f.line_revenue) FILTER (WHERE f.transaction_type = 'Cancellation' AND f.is_product), 0), 2) AS product_cancellation_value
FROM dw.fact_sales f
JOIN dw.dim_country co ON co.country_key = f.country_key
GROUP BY co.country_name
HAVING COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale') >= 50
ORDER BY cancellation_rate_pct DESC, co.country_name
LIMIT 10;


/* =============================================================================
   E. GEOGRAPHICAL ANALYSIS
   ============================================================================= */

-- @@QUERY Q28
/* Query ID          : Q28
   Business question : Which countries generate the highest revenue and what is their contribution?
   Explanation       : Revenue per country with RANK, share of total and cumulative share.
   Output columns    : country_rank, country_name, total_revenue, revenue_share_pct, cumulative_share_pct
   Business relevance: Country contribution chart and table (Geographical page).
   Learning objective: RANK + share + cumulative share in one query. */
WITH country_revenue AS (
    SELECT co.country_name, SUM(f.line_revenue) AS total_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_country co ON co.country_key = f.country_key
    WHERE f.transaction_type = 'Sale'
    GROUP BY co.country_name
)
SELECT RANK() OVER (ORDER BY total_revenue DESC)                                     AS country_rank,
       country_name,
       ROUND(total_revenue, 2)                                                       AS total_revenue,
       ROUND(100.0 * total_revenue / SUM(total_revenue) OVER (), 2)                  AS revenue_share_pct,
       ROUND(100.0 * SUM(total_revenue) OVER (ORDER BY total_revenue DESC
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
             / SUM(total_revenue) OVER (), 2)                                        AS cumulative_share_pct
FROM country_revenue
ORDER BY country_rank;


-- @@QUERY Q29
/* Query ID          : Q29
   Business question : Which countries contribute the most orders, and how do order
                       size and customer counts differ by country?
   Explanation       : Orders, identified customers, AOV and orders per customer by country.
   Output columns    : country_name, orders, order_share_pct, customers, average_order_value, orders_per_customer
   Business relevance: Distinguishes markets with many small orders from few large ones.
   Learning objective: Several ratios per group; NULLIF guard. */
SELECT co.country_name,
       COUNT(DISTINCT f.invoice_no)                                                       AS orders,
       ROUND(100.0 * COUNT(DISTINCT f.invoice_no) / SUM(COUNT(DISTINCT f.invoice_no)) OVER (), 2) AS order_share_pct,
       COUNT(DISTINCT f.customer_key) FILTER (WHERE f.customer_key <> 0)                  AS customers,
       ROUND(SUM(f.line_revenue) / COUNT(DISTINCT f.invoice_no), 2)                       AS average_order_value,
       ROUND(1.0 * COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.customer_key <> 0)
             / NULLIF(COUNT(DISTINCT f.customer_key) FILTER (WHERE f.customer_key <> 0), 0), 1) AS orders_per_customer
FROM dw.fact_sales f
JOIN dw.dim_country co ON co.country_key = f.country_key
WHERE f.transaction_type = 'Sale'
GROUP BY co.country_name
ORDER BY orders DESC
LIMIT 15;


-- @@QUERY Q30
/* Query ID          : Q30
   Business question : How do UK and international revenue compare each month?
   Explanation       : Pivot with conditional SUM on the market attribute of dim_country.
   Output columns    : year_month, uk_revenue, international_revenue, international_share_pct
   Business relevance: Tracks dependence on the home market.
   Learning objective: Pivoting rows to columns with FILTER. */
SELECT d.year_month,
       ROUND(SUM(f.line_revenue) FILTER (WHERE co.market = 'United Kingdom'), 2) AS uk_revenue,
       ROUND(SUM(f.line_revenue) FILTER (WHERE co.market = 'International'), 2)  AS international_revenue,
       ROUND(100.0 * SUM(f.line_revenue) FILTER (WHERE co.market = 'International')
             / SUM(f.line_revenue), 1)                                          AS international_share_pct
FROM dw.fact_sales f
JOIN dw.dim_date d     ON d.date_key = f.date_key
JOIN dw.dim_country co ON co.country_key = f.country_key
WHERE f.transaction_type = 'Sale'
GROUP BY d.year_month_key, d.year_month
ORDER BY d.year_month_key;


/* =============================================================================
   F. ADVANCED SQL PATTERNS
   ============================================================================= */

-- @@QUERY Q31
/* Query ID          : Q31
   Business question : Which merchandise stock codes exist in the data but were never
                       sold on a valid Sale line?
   Explanation       : LEFT JOIN from the product dimension to a sales subquery; rows with
                       no match (NULL) are products that only appear on cancellations,
                       stock adjustments or zero-price lines.
   Output columns    : products_never_sold, example_codes
   Business relevance: Catalogue hygiene - codes that carry no revenue.
   Learning objective: LEFT JOIN ... WHERE right side IS NULL (anti-join); STRING_AGG. */
SELECT COUNT(*)                                                                    AS products_never_sold,
       STRING_AGG(p.stock_code, ', ' ORDER BY p.stock_code COLLATE "C")
           FILTER (WHERE rn <= 10)                                                 AS example_codes
FROM (
    SELECT p.*, ROW_NUMBER() OVER (ORDER BY p.stock_code COLLATE "C") AS rn
    FROM dw.dim_product p
    LEFT JOIN (SELECT DISTINCT product_key FROM dw.fact_sales WHERE transaction_type = 'Sale') s
           ON s.product_key = p.product_key
    WHERE p.is_product AND s.product_key IS NULL
) p;


-- @@QUERY Q32
/* Query ID          : Q32
   Business question : What are the top 3 products in each of the 5 largest international markets?
   Explanation       : ROW_NUMBER() OVER (PARTITION BY country ...) restarts the numbering
                       for each country; a subquery picks the top 5 non-UK countries.
   Output columns    : country_name, product_position, stock_code, description, total_revenue
   Business relevance: Market-specific product focus for international campaigns.
   Learning objective: PARTITION BY (top-N per group), subquery with IN. */
WITH country_product AS (
    SELECT co.country_name, p.stock_code, p.description, SUM(f.line_revenue) AS total_revenue
    FROM dw.fact_sales f
    JOIN dw.dim_country co ON co.country_key = f.country_key
    JOIN dw.dim_product p  ON p.product_key  = f.product_key
    WHERE f.transaction_type = 'Sale'
      AND co.country_name IN (
            SELECT co2.country_name
            FROM dw.fact_sales f2
            JOIN dw.dim_country co2 ON co2.country_key = f2.country_key
            WHERE f2.transaction_type = 'Sale' AND co2.market = 'International'
            GROUP BY co2.country_name
            ORDER BY SUM(f2.line_revenue) DESC
            LIMIT 5)
    GROUP BY co.country_name, p.stock_code, p.description
)
SELECT country_name, product_position, stock_code, description, ROUND(total_revenue, 2) AS total_revenue
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY country_name
                                   ORDER BY total_revenue DESC, stock_code COLLATE "C") AS product_position
      FROM country_product) r
WHERE product_position <= 3
ORDER BY country_name, product_position;


-- @@QUERY Q33
/* Query ID          : Q33
   Business question : How does every transaction type contribute to the total value
                       of all lines (reconciliation of the revenue definitions)?
   Explanation       : Groups the whole fact table by transaction type and product flag.
                       Proves which lines are in and out of Total Revenue and Net Revenue.
   Output columns    : transaction_type, is_product, lines, invoices, total_value, in_total_revenue, in_net_revenue
   Business relevance: Transparency - anyone can reconcile the KPIs back to source lines.
   Learning objective: GROUP BY multiple columns; CASE for documentation columns. */
SELECT transaction_type,
       is_product,
       COUNT(*)                         AS lines,
       COUNT(DISTINCT invoice_no)       AS invoices,
       ROUND(SUM(line_revenue), 2)      AS total_value,
       CASE WHEN transaction_type = 'Sale' THEN 'Yes' ELSE 'No' END AS in_total_revenue,
       CASE WHEN transaction_type = 'Sale'
              OR (transaction_type = 'Cancellation' AND is_product) THEN 'Yes' ELSE 'No' END AS in_net_revenue
FROM dw.fact_sales
GROUP BY transaction_type, is_product
ORDER BY transaction_type, is_product DESC;

-- End of file: 33 queries.
