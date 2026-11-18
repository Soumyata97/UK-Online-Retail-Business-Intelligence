/* =============================================================================
   UK Online Retail Sales & Customer Analytics
   File      : 10_Database_Schema.sql
   Purpose   : Create the schemas and the RAW landing table.
   Database  : online_retail_bi   (PostgreSQL 16+; written for PostgreSQL 18)
   Run order : 1st  (run while connected to the online_retail_bi database)
   Next step : Import Dataset/raw/online_retail_raw.csv into staging.raw_online_retail
               (see SQL/12_Data_Import_Instructions.md), then run 11_Table_Creation.sql

   Design notes
   ------------
   * Two schemas keep the layers apart:
       staging  -> raw landing table + cleaned, typed table (data preparation layer)
       dw       -> star schema used by SQL analysis and Power BI (presentation layer)
   * The raw table stores every source column as TEXT so that the import can
     never fail or silently coerce values. The original data is preserved exactly
     as published; all typing and cleaning happens in 07_Data_Cleaning_Script.sql.
   * source_row_id is a lineage column added during the xlsx -> csv conversion.
     It is the 1-based row position in the official "Online Retail.xlsx" file
     (header excluded) and lets every cleaned row be traced back to the source.
   * This script is re-runnable. WARNING: re-running it DROPS the raw table and
     any imported data, so you will need to import the CSV again.
   ============================================================================= */

-- 1. Schemas ------------------------------------------------------------------
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS dw;

COMMENT ON SCHEMA staging IS 'Data preparation layer: raw landing table and cleaned typed table.';
COMMENT ON SCHEMA dw      IS 'Presentation layer: star schema (facts and dimensions) for analysis and Power BI.';

-- 2. Raw landing table -------------------------------------------------------
-- Dependent objects (the cleaned table is rebuilt by later scripts) are dropped
-- with CASCADE so the script can be re-run from a clean state.
DROP TABLE IF EXISTS staging.raw_online_retail CASCADE;

CREATE TABLE staging.raw_online_retail (
    source_row_id  INTEGER     NOT NULL,   -- lineage: row position in the official xlsx
    invoice_no     TEXT,                   -- source column InvoiceNo
    stock_code     TEXT,                   -- source column StockCode
    description    TEXT,                   -- source column Description
    quantity       TEXT,                   -- source column Quantity
    invoice_date   TEXT,                   -- source column InvoiceDate (ISO yyyy-mm-dd hh:mi:ss)
    unit_price     TEXT,                   -- source column UnitPrice (GBP)
    customer_id    TEXT,                   -- source column CustomerID (blank = missing)
    country        TEXT,                   -- source column Country
    CONSTRAINT pk_raw_online_retail PRIMARY KEY (source_row_id)
);

COMMENT ON TABLE staging.raw_online_retail IS
  'Unmodified UCI Online Retail data (DOI 10.24432/C5BW33). All columns TEXT. Expected 541,909 rows.';
COMMENT ON COLUMN staging.raw_online_retail.source_row_id IS
  'Row position in the official Online Retail.xlsx (1-based, header excluded). Added for lineage.';

-- 3. Quick check (should return 0 before the import, 541909 after it) --------
SELECT COUNT(*) AS raw_row_count FROM staging.raw_online_retail;
