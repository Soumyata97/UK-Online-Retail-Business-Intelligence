# 12 · Data Import Instructions (PostgreSQL 18 + pgAdmin 4 on Windows)

These steps load the raw data into `staging.raw_online_retail` and build the whole database.
Everything here was executed successfully by the author on **PostgreSQL 16.15** (Linux) with `psql`. The pgAdmin clicks below are written for pgAdmin 4 (version 8/9) on Windows and have **not** been executed on your computer.

> Never type your PostgreSQL password into any project file. pgAdmin and Power BI store it themselves.

---

## Files you need

| File | Purpose |
|---|---|
| `Dataset/raw/online_retail_raw.csv` | The official UCI data converted to UTF-8 CSV (541,909 rows + header, 9 columns, ~51 MB) |
| `SQL/10_Database_Schema.sql` | Creates schemas `staging` and `dw` and the raw table |
| `SQL/11_Table_Creation.sql` | Creates the cleaned table, star schema, constraints, indexes |
| `SQL/07_Data_Cleaning_Script.sql` | Cleans the data and loads the star schema |
| `SQL/08_Data_Validation_Script.sql` | 18 PASS/FAIL checks on the cleaning |
| `SQL/13_Database_Validation.sql` | 14 PASS/FAIL checks on structure and integrity |
| `SQL/15_SQL_Analysis_Queries.sql` | 33 analysis queries |
| `SQL/17_RFM_Analysis.sql` | RFM segmentation |

Tip: extract the project to a short path without spaces and outside OneDrive, e.g. `C:\Projects\UK-Online-Retail-Business-Intelligence`.

---

## Execution order (summary)

| # | Action | Expected result |
|---|---|---|
| 1 | Create database `online_retail_bi` (pgAdmin GUI) | Database appears in the tree |
| 2 | Run `10_Database_Schema.sql` | `raw_row_count = 0` |
| 3 | Import `online_retail_raw.csv` into `staging.raw_online_retail` | 541,909 rows |
| 4 | Run `11_Table_Creation.sql` | `Tables created` |
| 5 | Run `07_Data_Cleaning_Script.sql` (30-120 s) | Cleaning log, step 3 = 536,641 |
| 6 | Run `08_Data_Validation_Script.sql` | 18 rows, all `PASS` |
| 7 | Run `13_Database_Validation.sql` | 14 rows, all `PASS` |
| 8 | Run queries in `15_SQL_Analysis_Queries.sql` one at a time | Match `Analysis_Outputs/sql_results/Qxx.csv` |
| 9 | Run `17_RFM_Analysis.sql` | Validation row `PASS` (4,334 = 4,334) |

The file numbers are deliverable IDs from the project brief, **not** the run order. Always follow the table above.

---

## Step 1 - Create the database

1. Open **pgAdmin 4** and expand **Servers → PostgreSQL 18** (enter your password when asked).
2. Right-click **Databases → Create → Database…**
3. **General** tab: Database = `online_retail_bi`, Owner = `postgres`.
4. **Definition** tab: Encoding = `UTF8` (leave Template, Collation and Character type as default).
5. Click **Save**.

## Step 2 - Run 10_Database_Schema.sql

1. Click the new **online_retail_bi** database, then **Tools → Query Tool** (or the Query Tool icon).
2. In the Query Tool click **Open File** (folder icon) → select `SQL\10_Database_Schema.sql`.
3. Press **F5** (Execute script). The result grid shows `raw_row_count = 0`.
4. Right-click **online_retail_bi → Refresh**. Under **Schemas** you now see `staging` and `dw`.

## Step 3 - Import the CSV (pgAdmin Import/Export dialog)

1. Expand **online_retail_bi → Schemas → staging → Tables**.
2. Right-click **raw_online_retail → Import/Export Data…**
3. **General** tab:
   - Switch the toggle to **Import**.
   - **Filename**: click the folder icon and select `Dataset\raw\online_retail_raw.csv` (if the file browser does not show it, set the file-type filter to *All Files*).
   - **Format**: `csv`
   - **Encoding**: `UTF8`
4. **Options** tab:
   - **Header**: ON
   - **Delimiter**: `,`
   - **Quote**: `"`   **Escape**: `"`
   - Leave **NULL String** empty (empty fields become NULL - this is how missing CustomerIDs and descriptions are stored).
5. **Columns** tab: keep all 9 columns in this order: `source_row_id, invoice_no, stock_code, description, quantity, invoice_date, unit_price, customer_id, country`.
6. Click **OK**. A notification shows the process; wait for **"Successfully completed"** (usually under a minute).
7. Check in the Query Tool:

```sql
SELECT COUNT(*) FROM staging.raw_online_retail;   -- expected 541909
```

### Alternative: PSQL Tool (if the dialog gives trouble)

Right-click **online_retail_bi → PSQL Tool**, then type (use forward slashes in the path):

```
\copy staging.raw_online_retail FROM 'C:/Projects/UK-Online-Retail-Business-Intelligence/Dataset/raw/online_retail_raw.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
```

Expected output: `COPY 541909`. (`\copy` reads the file with your Windows user's permissions, which avoids the "permission denied" error a server-side `COPY` gives when the PostgreSQL service account cannot read your folder.)

### Import troubleshooting

| Error | Cause | Fix |
|---|---|---|
| `extra data after last expected column` | Wrong delimiter/quote settings | Delimiter `,`, Quote `"`, Header ON |
| `invalid byte sequence for encoding` | Encoding not UTF8 | Set Encoding = UTF8 |
| `duplicate key value violates unique constraint "pk_raw_online_retail"` | You imported twice | Re-run `10_Database_Schema.sql` (empties the table) and import once |
| `could not open file … Permission denied` | Server-side COPY | Use the pgAdmin dialog or `\copy` |
| Row count 541,910 | Header imported as data | Header must be ON (and the import would fail on the integer column anyway) |

## Step 4 - Run 11_Table_Creation.sql

Query Tool → Open File → `SQL\11_Table_Creation.sql` → **F5**. Result: `Tables created`. NOTICE messages such as *table "fact_sales" does not exist, skipping* are normal on the first run.

## Step 5 - Run 07_Data_Cleaning_Script.sql

Open and run with **F5**. It takes roughly 30-120 seconds. The final result grid is the cleaning log; compare with these values (from the author's run):

| step_no | step_name | row_count |
|---|---|---|
| 1 | Raw rows imported | 541,909 |
| 2 | Exact duplicate lines excluded | 5,268 |
| 3 | Rows in cleaned table | 536,641 |
| 4 | Classified as Sale | 522,540 |
| 5 | Classified as Cancellation | 9,251 |
| 6 | Classified as Non-Product | 2,354 |
| 7 | Classified as Stock Adjustment | 1,336 |
| 8 | Classified as Zero Price | 1,157 |
| 9 | Classified as Adjustment | 3 |
| 10 | Cleaned lines without CustomerID (kept) | 135,037 |
| 11 | Cleaned lines without description (kept) | 1,454 |
| 12-16 | dim_date / dim_country / dim_product / dim_customer / fact_sales | 730 / 38 / 3,958 / 4,373 / 536,641 |

## Steps 6-7 - Validation

Run `08_Data_Validation_Script.sql` then `13_Database_Validation.sql`. Every `status` must be `PASS`. `13` returns three result sets; pgAdmin shows the last one (indexes) - to see the PASS/FAIL table, highlight only the first `WITH checks AS (...) SELECT ...;` statement and press F5.

## Step 8 - Analysis queries

Open `15_SQL_Analysis_Queries.sql`, highlight one query (from `SELECT`/`WITH` to its `;`) and press **F5**. Compare with `Analysis_Outputs/sql_results/<QueryID>.csv`. To save a result: click **Save results to file** (download icon above the grid).

## Step 9 - RFM

Run `17_RFM_Analysis.sql`. It creates `dw.rfm_customer` and copies the segment to `dw.dim_customer`. Highlight-and-run each of the three result queries at the end to see the summary, score boundaries and the PASS check.

## Re-running

- `07` can be re-run at any time (it empties and reloads everything; then re-run `17`).
- `11` drops and recreates all tables except the raw table (then run `07` and `17`).
- `10` **drops the raw table** - you must import the CSV again afterwards.

## Optional: export the cleaned CSV yourself

`Dataset/cleaned/09_Cleaned_Online_Retail.csv` was exported from PostgreSQL with this PSQL Tool command (adjust the path):

```
\copy (SELECT source_row_id, invoice_no, stock_code, description, quantity, TO_CHAR(invoice_datetime,'YYYY-MM-DD HH24:MI:SS') AS invoice_datetime, invoice_date, unit_price, customer_id, country, line_revenue, transaction_type, CASE WHEN is_product THEN 'true' ELSE 'false' END AS is_product, CASE WHEN is_cancellation THEN 'true' ELSE 'false' END AS is_cancellation, CASE WHEN has_customer_id THEN 'true' ELSE 'false' END AS has_customer_id FROM staging.clean_online_retail ORDER BY source_row_id) TO 'C:/Projects/UK-Online-Retail-Business-Intelligence/Dataset/cleaned/my_export.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
```

Compare it with the shipped file (Windows PowerShell): `Get-FileHash .\Dataset\cleaned\my_export.csv` vs the SHA-256 in `Dataset/checksums.txt`.
