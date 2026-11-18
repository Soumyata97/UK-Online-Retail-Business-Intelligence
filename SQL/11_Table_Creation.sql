/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 11_Table_Creation.sql
   Purpose   : Create the cleaned staging table, the star schema tables,
               constraints and indexes. Tables are created EMPTY here and are
               populated by 07_Data_Cleaning_Script.sql.
   Run order : 2nd  (after 10_Database_Schema.sql AND after the CSV import)
   Next step : 07_Data_Cleaning_Script.sql

   Star schema (grain of the fact table = ONE source transaction line)
   -------------------------------------------------------------------
        dw.dim_date ----<  dw.fact_sales  >---- dw.dim_product
                              |      |
        dw.dim_customer ------+      +------ dw.dim_country

   * Surrogate keys (product_key, customer_key, country_key) are integers so the
     fact table stays narrow and joins are fast.
   * date_key uses the readable "smart key" format YYYYMMDD (e.g. 20111209).
   * customer_key = 0 is the documented "Unknown customer" member. It is used for
     the 135,080 source lines that have no CustomerID. It does NOT invent an
     identity: its customer_id is NULL and it is excluded from customer metrics.
   * Source identifiers (invoice_no, stock_code, customer_id, source_row_id) are
     preserved unchanged (stock_code is trimmed and upper-cased - see 06 doc).
   * Re-runnable: drops and recreates the objects (data is reloaded by 07).
   ============================================================================= */

DROP TABLE IF EXISTS dw.rfm_customer          CASCADE;   -- created by 17_RFM_Analysis.sql
DROP TABLE IF EXISTS dw.fact_sales            CASCADE;
DROP TABLE IF EXISTS dw.dim_customer          CASCADE;
DROP TABLE IF EXISTS dw.dim_product           CASCADE;
DROP TABLE IF EXISTS dw.dim_country           CASCADE;
DROP TABLE IF EXISTS dw.dim_date              CASCADE;
DROP TABLE IF EXISTS staging.clean_online_retail CASCADE;
DROP TABLE IF EXISTS staging.cleaning_log     CASCADE;

-- -----------------------------------------------------------------------------
-- 1. Cleaning log: record counts captured at each cleaning step
-- -----------------------------------------------------------------------------
CREATE TABLE staging.cleaning_log (
    step_no        INTEGER      NOT NULL PRIMARY KEY,
    step_name      TEXT         NOT NULL,
    rule_applied   TEXT         NOT NULL,
    row_count      BIGINT       NOT NULL,
    logged_at      TIMESTAMP    NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- 2. Cleaned, typed transaction lines (exact duplicates removed, rows classified)
-- -----------------------------------------------------------------------------
CREATE TABLE staging.clean_online_retail (
    source_row_id      INTEGER        NOT NULL,
    invoice_no         VARCHAR(10)    NOT NULL,
    stock_code         VARCHAR(20)    NOT NULL,   -- trimmed + upper-cased
    description        VARCHAR(255),              -- trimmed; NULL kept where source is missing
    quantity           INTEGER        NOT NULL,
    invoice_datetime   TIMESTAMP      NOT NULL,
    invoice_date       DATE           NOT NULL,
    unit_price         NUMERIC(10,3)  NOT NULL,
    customer_id        INTEGER,                   -- NULL kept where source is missing
    country            VARCHAR(50)    NOT NULL,
    line_revenue       NUMERIC(14,3)  NOT NULL,   -- quantity * unit_price (GBP)
    transaction_type   VARCHAR(20)    NOT NULL,
    is_product         BOOLEAN        NOT NULL,
    is_cancellation    BOOLEAN        NOT NULL,
    has_customer_id    BOOLEAN        NOT NULL,
    CONSTRAINT pk_clean_online_retail PRIMARY KEY (source_row_id),
    CONSTRAINT fk_clean_raw FOREIGN KEY (source_row_id)
        REFERENCES staging.raw_online_retail (source_row_id),
    CONSTRAINT ck_clean_transaction_type CHECK (transaction_type IN
        ('Sale','Cancellation','Non-Product','Stock Adjustment','Zero Price','Adjustment'))
);

-- -----------------------------------------------------------------------------
-- 3. Dimension: date (full calendar years 2010-2011 for time intelligence)
-- -----------------------------------------------------------------------------
CREATE TABLE dw.dim_date (
    date_key           INTEGER      NOT NULL,   -- YYYYMMDD
    full_date          DATE         NOT NULL,
    day_of_month       SMALLINT     NOT NULL,
    day_name           VARCHAR(9)   NOT NULL,
    day_of_week_iso    SMALLINT     NOT NULL,   -- 1 = Monday ... 7 = Sunday
    is_weekend         BOOLEAN      NOT NULL,
    week_start_date    DATE         NOT NULL,   -- Monday of the ISO week
    iso_week           SMALLINT     NOT NULL,
    month_number       SMALLINT     NOT NULL,
    month_name         VARCHAR(9)   NOT NULL,
    month_short        CHAR(3)      NOT NULL,
    quarter_number     SMALLINT     NOT NULL,
    quarter_label      CHAR(2)      NOT NULL,   -- Q1..Q4
    year_number        SMALLINT     NOT NULL,
    year_month         CHAR(7)      NOT NULL,   -- e.g. 2011-03
    year_month_key     INTEGER      NOT NULL,   -- e.g. 201103 (use to sort year_month)
    is_in_data_range   BOOLEAN      NOT NULL,   -- TRUE between 2010-12-01 and 2011-12-09
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key),
    CONSTRAINT uq_dim_date_full_date UNIQUE (full_date)
);

-- -----------------------------------------------------------------------------
-- 4. Dimension: country (country of the transaction line)
-- -----------------------------------------------------------------------------
CREATE TABLE dw.dim_country (
    country_key        INTEGER      NOT NULL GENERATED ALWAYS AS IDENTITY,
    country_name       VARCHAR(50)  NOT NULL,   -- exactly as in the source
    map_country_name   VARCHAR(50),             -- name a map visual can geocode (NULL = not mappable)
    market             VARCHAR(20)  NOT NULL,   -- 'United Kingdom' or 'International'
    is_mappable        BOOLEAN      NOT NULL,
    CONSTRAINT pk_dim_country PRIMARY KEY (country_key),
    CONSTRAINT uq_dim_country_name UNIQUE (country_name)
);

-- -----------------------------------------------------------------------------
-- 5. Dimension: product (one row per cleaned stock code)
-- -----------------------------------------------------------------------------
CREATE TABLE dw.dim_product (
    product_key        INTEGER      NOT NULL GENERATED ALWAYS AS IDENTITY,
    stock_code         VARCHAR(20)  NOT NULL,
    description        VARCHAR(255) NOT NULL,   -- most frequent description (see 06 doc)
    description_variants SMALLINT   NOT NULL,   -- number of distinct descriptions seen
    item_type          VARCHAR(30)  NOT NULL,   -- from documented service codes; NOT a product category
    is_product         BOOLEAN      NOT NULL,
    CONSTRAINT pk_dim_product PRIMARY KEY (product_key),
    CONSTRAINT uq_dim_product_stock_code UNIQUE (stock_code)
);

-- -----------------------------------------------------------------------------
-- 6. Dimension: customer
-- -----------------------------------------------------------------------------
CREATE TABLE dw.dim_customer (
    customer_key       INTEGER      NOT NULL,   -- 0 = Unknown (no CustomerID in source)
    customer_id        INTEGER,                 -- source CustomerID (NULL only for key 0)
    customer_label     VARCHAR(40)  NOT NULL,
    primary_country    VARCHAR(50),             -- country on most of the customer's lines
    is_known_customer  BOOLEAN      NOT NULL,
    -- RFM attributes are filled by 17_RFM_Analysis.sql
    rfm_segment        VARCHAR(30),
    r_score            SMALLINT,
    f_score            SMALLINT,
    m_score            SMALLINT,
    CONSTRAINT pk_dim_customer PRIMARY KEY (customer_key),
    CONSTRAINT uq_dim_customer_id UNIQUE (customer_id),
    CONSTRAINT ck_dim_customer_unknown CHECK (
        (customer_key = 0 AND customer_id IS NULL) OR (customer_key > 0 AND customer_id IS NOT NULL))
);

-- -----------------------------------------------------------------------------
-- 7. Fact: sales (grain = one cleaned source transaction line)
-- -----------------------------------------------------------------------------
CREATE TABLE dw.fact_sales (
    source_row_id      INTEGER        NOT NULL,   -- degenerate key back to the source line
    invoice_no         VARCHAR(10)    NOT NULL,   -- degenerate dimension (order number)
    date_key           INTEGER        NOT NULL,
    product_key        INTEGER        NOT NULL,
    customer_key       INTEGER        NOT NULL,
    country_key        INTEGER        NOT NULL,
    invoice_datetime   TIMESTAMP      NOT NULL,
    quantity           INTEGER        NOT NULL,
    unit_price         NUMERIC(10,3)  NOT NULL,
    line_revenue       NUMERIC(14,3)  NOT NULL,
    transaction_type   VARCHAR(20)    NOT NULL,
    cancellation_status VARCHAR(13)   NOT NULL,   -- 'Cancelled' / 'Not Cancelled'
    is_product         BOOLEAN        NOT NULL,
    has_customer_id    BOOLEAN        NOT NULL,
    CONSTRAINT pk_fact_sales PRIMARY KEY (source_row_id),
    CONSTRAINT fk_fact_date     FOREIGN KEY (date_key)     REFERENCES dw.dim_date (date_key),
    CONSTRAINT fk_fact_product  FOREIGN KEY (product_key)  REFERENCES dw.dim_product (product_key),
    CONSTRAINT fk_fact_customer FOREIGN KEY (customer_key) REFERENCES dw.dim_customer (customer_key),
    CONSTRAINT fk_fact_country  FOREIGN KEY (country_key)  REFERENCES dw.dim_country (country_key),
    CONSTRAINT ck_fact_cancel_status CHECK (cancellation_status IN ('Cancelled','Not Cancelled')),
    CONSTRAINT ck_fact_revenue CHECK (line_revenue = quantity * unit_price)
);

-- Indexes on foreign keys and common filters (PostgreSQL does not index FKs automatically)
CREATE INDEX ix_fact_sales_date      ON dw.fact_sales (date_key);
CREATE INDEX ix_fact_sales_product   ON dw.fact_sales (product_key);
CREATE INDEX ix_fact_sales_customer  ON dw.fact_sales (customer_key);
CREATE INDEX ix_fact_sales_country   ON dw.fact_sales (country_key);
CREATE INDEX ix_fact_sales_invoice   ON dw.fact_sales (invoice_no);
CREATE INDEX ix_fact_sales_type      ON dw.fact_sales (transaction_type);
CREATE INDEX ix_clean_invoice        ON staging.clean_online_retail (invoice_no);
CREATE INDEX ix_clean_customer       ON staging.clean_online_retail (customer_id);

COMMENT ON TABLE dw.fact_sales IS 'Grain: one cleaned source transaction line (exact duplicates removed). All transaction types kept and labelled.';
COMMENT ON COLUMN dw.fact_sales.transaction_type IS 'Sale | Cancellation | Non-Product | Stock Adjustment | Zero Price | Adjustment (rules in 06_Data_Cleaning_Methodology.docx)';

SELECT 'Tables created' AS status;
