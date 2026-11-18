# PROJECT STATUS

**Prepared:** 17 November 2026 · **Build environment:** Linux, PostgreSQL 16.15, Python 3.13 (pandas), LibreOffice (for document/formula checks). **Not available in the build environment:** Windows, PostgreSQL 18, pgAdmin, Power BI Desktop.

> **Actual PBIX availability: NO.** `PowerBI/dashboard.pbix` does not exist in this ZIP. It must be built locally with `PowerBI/Dashboard_Build_Guide.docx`. No Power BI screenshots exist; the images in `PowerBI/Wireframes/` are Python renderings of the SQL results.

Status key: **Executed** = run on the full dataset in the build environment with the results shown · **Generated, untested** = written but could not be run here · **Local** = needs your PC.

---

## 1. Completed and executed (build environment)

| File | Evidence |
|---|---|
| `Dataset/raw/online_retail_raw.csv` | Converted from the official xlsx (SHA-256 `43465a06…676d`); converter re-run reproduces it byte-for-byte |
| `SQL/10_Database_Schema.sql` | Executed; import of 541,909 rows succeeded with `\copy` |
| `SQL/11_Table_Creation.sql` | Executed (also re-run to test re-runnability) |
| `SQL/07_Data_Cleaning_Script.sql` | Executed; cleaning log 541,909 → 536,641; re-run twice safely |
| `SQL/08_Data_Validation_Script.sql` | Executed; **18/18 PASS** |
| `SQL/13_Database_Validation.sql` | Executed; **14/14 PASS** |
| `SQL/15_SQL_Analysis_Queries.sql` | All **33** queries executed; outputs in `Analysis_Outputs/sql_results/`; identical after a full rebuild |
| `SQL/17_RFM_Analysis.sql` | Executed; 4,334 customers scored; validation PASS |
| `SQL/run_all_psql.sql` | Executed end-to-end from an empty database with psql |
| `Dataset/cleaned/09_Cleaned_Online_Retail.csv` | Exported from PostgreSQL; Python implementation produces a byte-identical file |
| `Python/convert_xlsx_to_csv.py`, `clean_online_retail.py`, `verify_kpis_and_rfm.py` | Executed; parity checks **IDENTICAL** |
| `Dataset/03_Dataset_Profile.xlsx`, `04_Data_Dictionary.xlsx`, `Analysis_Outputs/18_RFM_Customer_Segmentation.xlsx`, `Testing/26_…xlsx` | Generated from real results; formulas recalculated with 0 errors |
| `Documentation/14_Data_Model_Diagram.png`, `23_Star_Schema.png`, `Analysis_Outputs/charts/*.png`, `PowerBI/Wireframes/*.png` | Rendered from the database design and SQL outputs |
| All `.docx` documents and `Presentation/29_Executive_Presentation.pptx` | Generated; every figure taken from the SQL outputs; rendered and visually checked |

## 2. Generated but untested

| File | Why untested | How to test |
|---|---|---|
| `PowerBI/21_Power_Query_M_Code.txt` | Power BI not available | START_HERE step 9; tests T-PQ-01/02 |
| `PowerBI/24_DAX_Measures.md` (27 measures) | Power BI not available | START_HERE step 10; tests T-DAX, T-TI, T-RK (expected values provided from SQL) |
| `PowerBI/UK_Retail_Theme.json` | Power BI not available | View → Themes → Browse |
| `PowerBI/Dashboard_Build_Guide.docx` instructions | Power BI not available | Follow it; tests T-SLC, T-SVP, T-VIS |
| pgAdmin click-paths in `START_HERE.md` / `12_Data_Import_Instructions.md` | pgAdmin GUI not available (the same SQL and `\copy` were executed) | START_HERE steps 4-6 |
| SQL on **PostgreSQL 18** | Tested on 16.15. Scripts use only long-standing features (identity columns, FILTER, window functions, CUME_DIST, PERCENTILE_CONT) | Tests T-LOC-01 to T-LOC-05 |

## 3. Files requiring local execution

| Step | Action | Files |
|---|---|---|
| Database | Create `online_retail_bi`, import CSV, run scripts | `SQL/*` (order in START_HERE step 6) |
| Verification | Compare with reference outputs | `Analysis_Outputs/sql_results/*.csv` |
| Optional | Re-create the CSV from the official xlsx | `Python/convert_xlsx_to_csv.py` |

## 4. Files requiring manual Power BI construction

| Deliverable | Status |
|---|---|
| `PowerBI/dashboard.pbix` | **Not created** - build locally |
| Power BI data model (5 tables, 4 relationships) | Instructions + M code provided |
| 27 DAX measures | Code + expected values provided |
| 5 report pages | Visual-by-visual guide + wireframes provided |
| `PowerBI/Screenshots/*.png` | Empty folder - capture after building |

## 5. Testing summary (`Testing/26_Data_Validation_Test_Cases.xlsx`)

| Status | Count |
|---|---:|
| Passed (executed in build environment) | 45 |
| Failed | 0 |
| Blocked | 0 |
| Not Executed (needs your PostgreSQL 18 / Power BI) | 48 |
| **Total** | **93** |

Defects found and fixed during testing (details in `Testing/27_Testing_Report.docx`): a re-run failure caused by the RFM foreign key; a Python negative-zero formatting difference; a boolean-parsing bug in the Python cross-check; product rankings distorted by two cancelled orders (fixed by ranking on Net Revenue).

## 6. Remaining validation tasks

- [ ] Import and run all SQL on PostgreSQL 18 (T-LOC-01 … T-LOC-05)
- [ ] Build the Power BI model and run Power Query tests (T-PQ, T-MOD)
- [ ] Create the 27 measures and compare with expected values (T-DAX, T-TI, T-RK)
- [ ] Build the five pages; test slicers and SQL-vs-Power BI totals (T-SLC, T-SVP)
- [ ] Save `PowerBI/dashboard.pbix` and screenshots (T-VIS)
- [ ] Update this file: PBIX available = Yes (date), local test results
- [ ] Replace the wireframe on slide 8 of the presentation and in README with real screenshots
- [ ] Choose a licence for your own code before publishing on GitHub

## 7. ZIP verification (performed before delivery)

| Check | Result |
|---|---|
| All expected files exist | See `MANIFEST.txt` (file list with sizes) |
| ZIP opens and extracts | Tested (extracted and re-listed) |
| No empty documents | All files > 0 bytes; documents opened/rendered |
| SQL scripts not truncated | Each script ends with its final statement; all executed |
| Folder structure | As in README |
| No credentials | Scanned for passwords/secrets: none (only instructions to type your own) |
| START_HERE.md and README.md present | Yes |
