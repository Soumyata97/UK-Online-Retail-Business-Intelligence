# Download instructions

The ZIP you received already contains the data ready to import (`Dataset/raw/online_retail_raw.csv`). Use these steps if you cloned the project from GitHub (the CSVs are not in the repository) or want to verify the data yourself.

## Option A - use the shipped CSV (no download)

Nothing to do. Go to `START_HERE.md` step 5.

## Option B - download from UCI and convert (requires Python)

1. Open https://archive.ics.uci.edu/dataset/352/online+retail and click **Download** (or download directly: https://archive.ics.uci.edu/static/public/352/online+retail.zip).
2. Extract `online+retail.zip`. It contains one file: **`Online Retail.xlsx`** (23,715,344 bytes).
3. Optional integrity check (PowerShell):
   ```powershell
   Get-FileHash "C:\Downloads\Online Retail.xlsx"
   # expected SHA256: 43465A06F2CCF7C8B5BD2892BC7DEFB52F97487934FE93B16AE4C3936424676D
   ```
4. Install Python 3.10+ from python.org (tick "Add python.exe to PATH"), then in the project folder:
   ```powershell
   python -m pip install -r Python\requirements.txt
   python Python\convert_xlsx_to_csv.py "C:\Downloads\Online Retail.xlsx" Dataset\raw\online_retail_raw.csv
   ```
   Expected output: `Rows read : 541,909` and a checksum match message. The result is byte-identical to the CSV shipped in the ZIP (tested by the author).

## Why not just "Save As CSV" in Excel?

Excel can do it (541,909 rows fit in a sheet) but it reformats dates according to your Windows regional settings, may change number formats and does not add the `source_row_id` lineage column, so the import table and scripts would not match. If you must use Excel, the converter script is the reliable route.

## Rebuilding the cleaned CSV

The cleaned file is produced by the SQL pipeline. After running the SQL scripts, export it with the `\copy` command in `SQL/12_Data_Import_Instructions.md`, or run the Python implementation:

```powershell
python Python\clean_online_retail.py Dataset\raw\online_retail_raw.csv Dataset\cleaned\09_Cleaned_Online_Retail.csv
```
