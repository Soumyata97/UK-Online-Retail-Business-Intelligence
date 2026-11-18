"""
UK Online Retail Sales & Customer Analytics
convert_xlsx_to_csv.py

Converts the official UCI file "Online Retail.xlsx" into the UTF-8 CSV that is
imported into staging.raw_online_retail. The project ZIP already contains the
result (Dataset/raw/online_retail_raw.csv), so running this is OPTIONAL. Use it
to prove for yourself that the shipped CSV is a faithful copy of the official file.

What it does (and nothing else):
  * adds source_row_id = 1-based row position in the xlsx (header excluded)
  * writes InvoiceDate as ISO text  yyyy-mm-dd hh:mm:ss
  * writes CustomerID as a whole number (Excel stores it as 17850.0), blank if missing
  * writes UnitPrice with Python's shortest exact representation (2.55, not 2.5499999)
  * keeps InvoiceNo / StockCode / Description / Country as text, untrimmed

Usage (Windows PowerShell, from the project folder):
    python Python\\convert_xlsx_to_csv.py "C:\\path\\to\\Online Retail.xlsx" Dataset\\raw\\online_retail_raw.csv

Requirements: pandas, openpyxl (pip install -r Python\\requirements.txt). Takes about 30-60 s.
"""
import hashlib
import sys

import pandas as pd

EXPECTED_XLSX_SHA256 = "43465a06f2ccf7c8b5bd2892bc7defb52f97487934fe93b16ae4c3936424676d"


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main(xlsx_path: str, csv_path: str) -> int:
    digest = sha256(xlsx_path)
    print(f"SHA-256 of input : {digest}")
    print("Matches the file used to build this project" if digest == EXPECTED_XLSX_SHA256
          else "WARNING: checksum differs from the file used to build this project")

    df = pd.read_excel(xlsx_path, dtype={"InvoiceNo": str, "StockCode": str,
                                         "Description": str, "Country": str})
    print(f"Rows read        : {len(df):,} (expected 541,909)")

    out = pd.DataFrame({"source_row_id": range(1, len(df) + 1)})
    out["InvoiceNo"] = df["InvoiceNo"]
    out["StockCode"] = df["StockCode"]
    out["Description"] = df["Description"]
    out["Quantity"] = df["Quantity"]
    out["InvoiceDate"] = df["InvoiceDate"].dt.strftime("%Y-%m-%d %H:%M:%S")
    out["UnitPrice"] = df["UnitPrice"].map(repr)
    out["CustomerID"] = df["CustomerID"].astype("Int64").astype("string")
    out["Country"] = df["Country"]
    out.to_csv(csv_path, index=False, encoding="utf-8", lineterminator="\n")
    print(f"Written          : {csv_path}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
