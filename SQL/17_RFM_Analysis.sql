/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 17_RFM_Analysis.sql
   Purpose   : Customer RFM (Recency, Frequency, Monetary) scoring and segmentation.
               Creates dw.rfm_customer and copies the segment onto dw.dim_customer
               so Power BI can slice every visual by segment.
   Run order : 7th  (after 07; can run before or after 15)
   Status    : Executed by the author on PostgreSQL 16.15. Results:
               Analysis_Outputs/18_RFM_Customer_Segmentation.xlsx

   IMPORTANT: these are analytical segments created for this portfolio project.
   They are NOT the retailer's own customer segments.

   METHODOLOGY
   -----------
   Population      Customers with a CustomerID and at least one Sale line.
   Reference date  2011-12-10 = the day after the last invoice in the dataset
                   (2011-12-09). Using the dataset's own end date (not today's date)
                   keeps recency meaningful for historical data.
   Recency (R)     Days from the customer's last Sale date to the reference date.
                   Smaller = better.
   Frequency (F)   Number of distinct Sale invoices (orders).
   Monetary (M)    Net revenue = Sale lines + the customer's product cancellation lines.
   Not scored      Customers whose net revenue is <= 0 (every purchase cancelled)
                   are excluded from scoring and labelled 'Not Scored'.
   Scores 1-5      score = CEIL(CUME_DIST() * 5), where CUME_DIST is calculated over the
                   scored customers ordered so that "better" values come last:
                     R: ORDER BY recency_days DESC   (most recent  -> 5)
                     F: ORDER BY frequency ASC       (most orders  -> 5)
                     M: ORDER BY monetary ASC        (highest spend-> 5)
                   CUME_DIST gives tied customers the SAME score (NTILE would split ties
                   arbitrarily, so results could change between runs). Because 35% of
                   customers have exactly one order, every one-order customer gets F = 2
                   and no customer gets F = 1. This is expected and documented.
   FM score        (F + M + 1) / 2 using integer division (= average rounded half up).
   Segments        Evaluated top to bottom; the first matching rule wins:
                     1 Champions           R >= 4 AND FM >= 4
                     2 Loyal Customers     R >= 3 AND FM >= 3
                     3 New Customers       R >= 4 AND frequency = 1
                     4 Potential Loyalists R >= 3
                     5 At Risk             R <= 2 AND FM >= 3
                     6 Hibernating         everything else (R <= 2 AND FM <= 2)
   ============================================================================= */

DROP TABLE IF EXISTS dw.rfm_customer;

CREATE TABLE dw.rfm_customer (
    customer_key         INTEGER        NOT NULL,
    customer_id          INTEGER        NOT NULL,
    first_purchase_date  DATE           NOT NULL,
    last_purchase_date   DATE           NOT NULL,
    recency_days         INTEGER        NOT NULL,
    frequency            INTEGER        NOT NULL,
    monetary             NUMERIC(14,2)  NOT NULL,
    r_score              SMALLINT,
    f_score              SMALLINT,
    m_score              SMALLINT,
    fm_score             SMALLINT,
    rfm_code             CHAR(3),
    rfm_segment          VARCHAR(30)    NOT NULL,
    reference_date       DATE           NOT NULL,
    CONSTRAINT pk_rfm_customer PRIMARY KEY (customer_key),
    CONSTRAINT fk_rfm_customer FOREIGN KEY (customer_key) REFERENCES dw.dim_customer (customer_key)
);

INSERT INTO dw.rfm_customer (
    customer_key, customer_id, first_purchase_date, last_purchase_date, recency_days,
    frequency, monetary, r_score, f_score, m_score, fm_score, rfm_code, rfm_segment, reference_date)
WITH params AS (
    SELECT DATE '2011-12-10' AS reference_date
),
base AS (
    SELECT f.customer_key,
           c.customer_id,
           MIN(f.invoice_datetime) FILTER (WHERE f.transaction_type = 'Sale')::date AS first_purchase_date,
           MAX(f.invoice_datetime) FILTER (WHERE f.transaction_type = 'Sale')::date AS last_purchase_date,
           COUNT(DISTINCT f.invoice_no) FILTER (WHERE f.transaction_type = 'Sale') AS frequency,
           ROUND(SUM(f.line_revenue), 2)                                           AS monetary
    FROM dw.fact_sales f
    JOIN dw.dim_customer c ON c.customer_key = f.customer_key
    WHERE f.customer_key <> 0
      AND (f.transaction_type = 'Sale' OR (f.transaction_type = 'Cancellation' AND f.is_product))
    GROUP BY f.customer_key, c.customer_id
    HAVING COUNT(*) FILTER (WHERE f.transaction_type = 'Sale') > 0
),
with_recency AS (
    SELECT b.*, (p.reference_date - b.last_purchase_date) AS recency_days, p.reference_date
    FROM base b CROSS JOIN params p
),
scored AS (
    SELECT w.*,
           CEIL(CUME_DIST() OVER (ORDER BY recency_days DESC) * 5)::smallint AS r_score,
           CEIL(CUME_DIST() OVER (ORDER BY frequency ASC)     * 5)::smallint AS f_score,
           CEIL(CUME_DIST() OVER (ORDER BY monetary ASC)      * 5)::smallint AS m_score
    FROM with_recency w
    WHERE monetary > 0
),
segmented AS (
    SELECT s.*,
           ((f_score + m_score + 1) / 2)::smallint AS fm_score
    FROM scored s
)
SELECT customer_key, customer_id, first_purchase_date, last_purchase_date, recency_days,
       frequency, monetary, r_score, f_score, m_score, fm_score,
       r_score::text || f_score::text || m_score::text,
       CASE
           WHEN r_score >= 4 AND fm_score >= 4 THEN 'Champions'
           WHEN r_score >= 3 AND fm_score >= 3 THEN 'Loyal Customers'
           WHEN r_score >= 4 AND frequency = 1 THEN 'New Customers'
           WHEN r_score >= 3                   THEN 'Potential Loyalists'
           WHEN r_score <= 2 AND fm_score >= 3 THEN 'At Risk'
           ELSE 'Hibernating'
       END,
       reference_date
FROM segmented
UNION ALL
SELECT customer_key, customer_id, first_purchase_date, last_purchase_date, recency_days,
       frequency, monetary, NULL, NULL, NULL, NULL, NULL, 'Not Scored (net revenue <= 0)', reference_date
FROM with_recency
WHERE monetary <= 0;

-- Copy segment and scores to the customer dimension (used by Power BI slicers)
UPDATE dw.dim_customer dc
SET rfm_segment = r.rfm_segment,
    r_score     = r.r_score,
    f_score     = r.f_score,
    m_score     = r.m_score
FROM dw.rfm_customer r
WHERE r.customer_key = dc.customer_key;

UPDATE dw.dim_customer SET rfm_segment = 'Unknown customer'
WHERE customer_key = 0;

UPDATE dw.dim_customer SET rfm_segment = 'No purchases in period'
WHERE customer_key <> 0 AND rfm_segment IS NULL;   -- customers that only have cancellation lines

-- -----------------------------------------------------------------------------
-- Result 1: segment summary
-- -----------------------------------------------------------------------------
SELECT rfm_segment,
       COUNT(*)                                                    AS customers,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)          AS pct_of_customers,
       ROUND(SUM(monetary), 2)                                     AS net_revenue,
       ROUND(100.0 * SUM(monetary) / SUM(SUM(monetary)) OVER (), 1) AS pct_of_revenue,
       ROUND(AVG(recency_days), 0)                                 AS avg_recency_days,
       ROUND(AVG(frequency), 1)                                    AS avg_frequency,
       ROUND(AVG(monetary), 2)                                     AS avg_monetary
FROM dw.rfm_customer
GROUP BY rfm_segment
ORDER BY CASE rfm_segment
            WHEN 'Champions' THEN 1 WHEN 'Loyal Customers' THEN 2 WHEN 'New Customers' THEN 3
            WHEN 'Potential Loyalists' THEN 4 WHEN 'At Risk' THEN 5 WHEN 'Hibernating' THEN 6
            ELSE 7 END;

-- -----------------------------------------------------------------------------
-- Result 2: score boundaries (shows exactly which raw values map to each score)
-- -----------------------------------------------------------------------------
SELECT 'R' AS dimension, r_score AS score, MIN(recency_days) AS min_value, MAX(recency_days) AS max_value, COUNT(*) AS customers
FROM dw.rfm_customer WHERE r_score IS NOT NULL GROUP BY r_score
UNION ALL
SELECT 'F', f_score, MIN(frequency), MAX(frequency), COUNT(*)
FROM dw.rfm_customer WHERE f_score IS NOT NULL GROUP BY f_score
UNION ALL
SELECT 'M', m_score, MIN(monetary), MAX(monetary), COUNT(*)
FROM dw.rfm_customer WHERE m_score IS NOT NULL GROUP BY m_score
ORDER BY dimension, score;

-- -----------------------------------------------------------------------------
-- Result 3: validation - every customer with a Sale line has exactly one RFM row
-- -----------------------------------------------------------------------------
SELECT (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales
         WHERE transaction_type = 'Sale' AND customer_key <> 0) AS customers_with_sales,
       (SELECT COUNT(*) FROM dw.rfm_customer)                   AS rfm_rows,
       CASE WHEN (SELECT COUNT(DISTINCT customer_key) FROM dw.fact_sales
                   WHERE transaction_type = 'Sale' AND customer_key <> 0)
               = (SELECT COUNT(*) FROM dw.rfm_customer)
            THEN 'PASS' ELSE 'FAIL' END                         AS status;
