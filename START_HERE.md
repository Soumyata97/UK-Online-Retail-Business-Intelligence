# START HERE - Local Execution Guide

**Project:** UK Online Retail Sales & Customer Analytics  
**For:** Windows 11 with PostgreSQL 18, pgAdmin 4, Power BI Desktop and VS Code installed.  
**Time needed:** about 30-45 minutes for the database (steps 1-7), 2-4 hours for the dashboard (steps 8-13).

> **What has and has not been run.** Every SQL script and Python script in this project was executed by the author on the full dataset in a Linux build environment with **PostgreSQL 16.15**, and all 32 validation checks passed. Nothing has been run on **your** PostgreSQL 18 or in Power BI Desktop. There is **no PBIX file** in this ZIP - you build it in steps 8-12. See `PROJECT_STATUS.md` for the full status.

> **Security.** You will type your PostgreSQL password only into pgAdmin and Power BI dialogs. Never write it into any project file.

---

## STEP 1 - Extract the ZIP

1. In File Explorer, right-click `UK-Online-Retail-Business-Intelligence.zip` → **Extract All…**
2. Extract to a short path **outside OneDrive**, for example `C:\Projects\`. You should end up with:
   `C:\Projects\UK-Online-Retail-Business-Intelligence\README.md` (and the folders below).
3. Check the folder contains: `Dataset`, `SQL`, `Python`, `Analysis_Outputs`, `PowerBI`, `Documentation`, `Testing`, `Presentation`, `Career`, `Learning`, plus `README.md`, `START_HERE.md`, `PROJECT_STATUS.md`.

Why outside OneDrive: OneDrive "files on demand" can leave the 51 MB CSV as a placeholder, which makes the import fail.

## STEP 2 - Open the project in VS Code

1. Open VS Code → **File → Open Folder…** → select `C:\Projects\UK-Online-Retail-Business-Intelligence` → **Select Folder** → trust the authors if asked.
2. Useful (optional) extensions: *Rainbow CSV*, *Python* (Microsoft), *SQLTools* + *SQLTools PostgreSQL/Cockroach Driver*.
3. Do not open the large CSVs in the editor (they are 51-72 MB); preview them with Rainbow CSV or Excel if needed.
4. You will mostly use VS Code to read the `.sql`, `.md` and `.txt` files; the SQL itself is run in pgAdmin.

## STEP 3 - Locate (or download) the original UCI dataset

- **Already included:** `Dataset\raw\online_retail_raw.csv` is the official `Online Retail.xlsx` converted to CSV (541,909 rows, values unchanged, plus a `source_row_id` column). The licence (CC BY 4.0) allows this. You can go straight to step 4.
- **To verify against the official source:** follow `Dataset\download_instructions.md` (download from https://archive.ics.uci.edu/dataset/352/online+retail, check the SHA-256, optionally re-create the CSV with the Python converter).
- Source and citation: `Dataset\source_information.md`.

## STEP 4 - Create the PostgreSQL database in pgAdmin

1. Open **pgAdmin 4** → expand **Servers → PostgreSQL 18** → enter your password.
   - If the server is not running: Windows key → *Services* → **postgresql-x64-18** → Start.
2. Right-click **Databases → Create → Database…**
3. **General:** Database = `online_retail_bi`; Owner = `postgres`.
4. **Definition:** Encoding = `UTF8`. Leave the rest as default → **Save**.
5. Click `online_retail_bi`, then **Tools → Query Tool**.
6. Query Tool → **Open File** → `SQL\10_Database_Schema.sql` → press **F5**. Expected: one row `raw_row_count = 0`.

## STEP 5 - Import the source data

1. In the tree: **online_retail_bi → Schemas → staging → Tables** (right-click *Tables → Refresh* if empty).
2. Right-click **raw_online_retail → Import/Export Data…**
   - **General:** toggle **Import**; Filename = `C:\Projects\UK-Online-Retail-Business-Intelligence\Dataset\raw\online_retail_raw.csv`; Format = **csv**; Encoding = **UTF8**.
   - **Options:** Header = **ON**; Delimiter = `,`; Quote = `"`; Escape = `"`; NULL string empty.
   - **Columns:** all 9 columns, in the existing order.
3. **OK** → wait for "Successfully completed".
4. Verify in the Query Tool: `SELECT COUNT(*) FROM staging.raw_online_retail;` → **541909**.

If the dialog fails, use the PSQL Tool alternative and the troubleshooting table in `SQL\12_Data_Import_Instructions.md`.

## STEP 6 - Run the SQL files in this order

Open each file in the Query Tool (**Open File**) and press **F5**. The file numbers are document IDs, **not** the run order.

| Order | File | What it does | Expected result | Time |
|---|---|---|---|---|
| 1st | `10_Database_Schema.sql` | Schemas + raw table *(done in step 4)* | `raw_row_count = 0` | 1 s |
| - | *CSV import* | *(done in step 5)* | 541,909 rows | < 1 min |
| 2nd | `11_Table_Creation.sql` | Cleaned table, star schema, keys, indexes | `Tables created` | 1 s |
| 3rd | `07_Data_Cleaning_Script.sql` | Cleans, classifies, loads star schema | Cleaning log; step 3 = **536,641** | 30-120 s |
| 4th | `08_Data_Validation_Script.sql` | 18 data checks | all **PASS** | 5-20 s |
| 5th | `13_Database_Validation.sql` | 14 structure checks | all **PASS** (see note) | 5 s |
| 6th | `15_SQL_Analysis_Queries.sql` | 33 analysis queries | see step 7 | run one at a time |
| 7th | `17_RFM_Analysis.sql` | RFM segments | `PASS` (4,334 = 4,334) | 5 s |

Notes:
- "NOTICE: … does not exist, skipping" messages are normal on a first run.
- pgAdmin shows only the **last** result of a multi-statement script. In `13` and `17`, highlight the statement you want to see (e.g. the first `WITH checks AS …;`) and press **F5**.
- Shortcut: the PSQL Tool can run everything at once with `SQL\run_all_psql.sql` (instructions inside the file).

## STEP 7 - Verify that the SQL queries work

1. Open `SQL\15_SQL_Analysis_Queries.sql`. Highlight query **Q01** (from `SELECT` to its `;`) → **F5**.
2. Expected (author's run): `total_revenue 10247219.32 · gross_positive_sales 10631048.74 · product_cancellations -475901.16 · net_revenue 9771318.16 · orders 19773 · customers 4334 · units_sold 5561387 · average_order_value 518.24`.
3. Repeat for any other query and compare with `Analysis_Outputs\sql_results\Q02.csv … Q33.csv` (open in Excel or VS Code).
4. Each query is explained in `Documentation\16_SQL_Explanation_Guide.docx`.
5. Record results in `Testing\26_Data_Validation_Test_Cases.xlsx` → column **Local Re-test Status** (tests T-LOC-01 to T-LOC-05).

## STEP 8 - Connect Power BI Desktop to PostgreSQL

1. Open Power BI Desktop → **Blank report**.
2. **File → Options and settings → Options → Current File → Data Load** → untick **Auto date/time** → OK.
3. **Home → Get data → More… → Database → PostgreSQL database → Connect.**
4. Server: `localhost:5432` · Database: `online_retail_bi` · Data Connectivity mode: **Import** → **OK**.
5. Credentials window → choose the **Database** tab (left) → User name `postgres` → Password: *your password* → **Connect**.
6. If you get an encryption/SSL error: **File → Options and settings → Data source settings** → select `localhost:5432;online_retail_bi` → **Edit Permissions** → untick **Encrypt connections** → OK → try again. (A default local PostgreSQL install has no SSL certificate.)
7. If Power BI says the connector needs additional components (Npgsql), install the provider linked from Microsoft's PostgreSQL connector page with the "GAC" option and restart Power BI. Recent versions of Power BI Desktop normally include it.
8. When the **Navigator** appears, click **Transform Data** (do not tick tables there - the next step creates clean queries).

## STEP 9 - Load tables and create relationships

1. In the Power Query Editor create two parameters: **Home → Manage Parameters → New Parameter**
   - `PgServer` · Type Text · Current Value `localhost:5432`
   - `PgDatabase` · Type Text · Current Value `online_retail_bi`
2. For each of **FactSales, DimDate, DimProduct, DimCustomer, DimCountry**:
   **Home → New Source → Blank Query** → rename it (Query Settings → Name) → **Home → Advanced Editor** → paste the matching block from `PowerBI\21_Power_Query_M_Code.txt` → **Done**.
3. Delete any query Power BI created from the Navigator (right-click → Delete) so only your five tables (and two parameters) remain.
4. **Home → Close & Apply.** Check rows in Table view: FactSales 536,641 · DimDate 730 · DimProduct 3,958 · DimCustomer 4,373 · DimCountry 38.
5. **Model view:** delete auto-created relationships, then drag to create these four (double-click each line to check *One to many*, *Single*):
   - `DimDate[Date]` → `FactSales[InvoiceDate]`
   - `DimProduct[ProductKey]` → `FactSales[ProductKey]`
   - `DimCustomer[CustomerKey]` → `FactSales[CustomerKey]`
   - `DimCountry[CountryKey]` → `FactSales[CountryKey]`
6. Select **DimDate → Table tools → Mark as date table → Date**.
7. Sort-by columns: `Month` by `MonthNumber`; `YearMonth` by `YearMonthKey`; `DayName` by `DayOfWeek`; `CustomerSegment` by `SegmentOrder`.
8. `DimCountry[MapCountry]` → Column tools → Data category → **Country/Region**.
9. Compare with `Documentation\23_Star_Schema.png`. Details: `Documentation\20_Power_Query_Guide.docx` and `22_Data_Model_Documentation.docx`.

## STEP 10 - Create the DAX measures

1. **Home → Enter data** → name the table `_Measures` → **Load**.
2. Select `_Measures` → **Table tools → New measure** → paste one measure from `PowerBI\24_DAX_Measures.md` → **Enter**. Repeat for all 27 measures, setting the format shown under each.
3. Delete the dummy `Column1` from `_Measures`.
4. Make a temporary page with Cards for Total Revenue, Net Revenue, Total Orders, Total Customers, Average Order Value and check them against the expected values in the DAX file (e.g. Total Revenue **£10,247,219.32**, Total Orders **19,773**).
5. Beginner explanations of every measure: `Documentation\25_DAX_Explanation_Guide.docx`.

## STEP 11 - Construct the dashboard

1. **View → Themes → Browse for themes** → `PowerBI\UK_Retail_Theme.json`.
2. Follow `PowerBI\Dashboard_Build_Guide.docx` page by page (5 pages, visual-by-visual field lists).
3. Use `PowerBI\Wireframes\Page1…Page5.png` as the layout reference (they show real numbers from SQL; they are not screenshots).
4. Add the five slicers (Date, Country, Product, Customer Segment, Cancellation Status) and **View → Sync slicers** across all pages.

## STEP 12 - Save the PBIX in the correct folder

1. **File → Save as** → navigate to `C:\Projects\UK-Online-Retail-Business-Intelligence\PowerBI\` → File name **`dashboard`** → **Save** → creates `PowerBI\dashboard.pbix`.
2. Capture each page (Windows + Shift + S) into `PowerBI\Screenshots\` with the names listed in `PowerBI\Screenshots\README.md`.

## STEP 13 - Verify the final project

1. Run the Power BI checks in `Testing\26_Data_Validation_Test_Cases.xlsx` (T-PQ, T-MOD, T-DAX, T-TI, T-RK, T-SLC, T-SVP, T-VIS) and fill **Local Re-test Status** and **Local Actual Result**.
2. Key reconciliations: monthly revenue matrix = `Analysis_Outputs\sql_results\Q02.csv`; Country = Germany → Total Revenue £205,381.15; Cancellation Status = Cancelled → Total Revenue blank.
3. Update `PROJECT_STATUS.md`: PBIX available = Yes, date tested, any failed tests.
4. Optionally replace slide 8 of `Presentation\29_Executive_Presentation.pptx` with your real screenshot.
5. Read `Documentation\28_Business_Insights_Report.docx` and `Learning\33_Learning_Guide.docx` before interviews.

## STEP 14 - Upload the finished project to GitHub

1. Create an account at https://github.com and install **Git for Windows** (https://git-scm.com/download/win) - or use **GitHub Desktop**.
2. On GitHub: **New repository** → name `UK-Online-Retail-Business-Intelligence` → Public → **do not** add a README (you already have one) → **Create repository**.
3. In VS Code: **Terminal → New Terminal** (PowerShell) in the project folder, then:
   ```powershell
   git init
   git add .
   git status            # confirm the large CSVs are NOT listed (they are in .gitignore)
   git commit -m "UK Online Retail BI portfolio project"
   git branch -M main
   git remote add origin https://github.com/<your-username>/UK-Online-Retail-Business-Intelligence.git
   git push -u origin main
   ```
   Git will open a browser window to sign in to GitHub the first time.
4. Before pushing, check that no file contains a password: `git grep -i "password"` should only show instruction text.
5. On the repository page add the description and topics from `Career\31_LinkedIn_Project_Description.docx`.
6. The `.gitignore` excludes `Dataset\raw\*.csv` and `Dataset\cleaned\*.csv` (51 MB and 72 MB). Visitors rebuild them with `Dataset\download_instructions.md`. Your `dashboard.pbix` (typically 10-25 MB) can be committed.

---

### Where to find things

| Need | File |
|---|---|
| Project summary | `README.md`, `Documentation\01_Project_Overview.docx` |
| What is tested / untested | `PROJECT_STATUS.md` |
| Cleaning rules | `Documentation\06_Data_Cleaning_Methodology.docx` |
| Findings | `Documentation\28_Business_Insights_Report.docx` |
| Interview prep | `Career\32_Interview_Preparation.docx` |
