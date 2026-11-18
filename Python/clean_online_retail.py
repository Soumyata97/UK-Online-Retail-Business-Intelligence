"""
UK Online Retail Sales & Customer Analytics
clean_online_retail.py

Independent pandas implementation of the cleaning rules R1-R11 in
SQL/07_Data_Cleaning_Script.sql. It exists to prove that the cleaning logic is
reproducible: the SQL and Python outputs must match line for line.

Usage (Windows PowerShell, from the project folder):
    python Python\\clean_online_retail.py Dataset\\raw\\online_retail_raw.csv Dataset\\cleaned\\python_cleaned.csv

Optional parity check against the CSV exported from PostgreSQL:
    python Python\\clean_online_retail.py Dataset\\raw\\online_retail_raw.csv Dataset\\cleaned\\python_cleaned.csv --compare Dataset\\cleaned\\09_Cleaned_Online_Retail.csv

Requirements: Python 3.10+, pandas  (pip install -r Python\\requirements.txt)
"""
import argparse
import sys
from decimal import Decimal

import pandas as pd

SERVICE_CODES = {"POST", "DOT", "C2", "M", "D", "S", "BANK CHARGES", "AMAZONFEE", "CRUK", "B"}
RAW_COLS = ["InvoiceNo", "StockCode", "Description", "Quantity",
            "InvoiceDate", "UnitPrice", "CustomerID", "Country"]
OUT_COLS = ["source_row_id", "invoice_no", "stock_code", "description", "quantity",
            "invoice_datetime", "invoice_date", "unit_price", "customer_id", "country",
            "line_revenue", "transaction_type", "is_product", "is_cancellation", "has_customer_id"]


def load_raw(path: str) -> pd.DataFrame:
    # Read every column as text, exactly like the TEXT columns of staging.raw_online_retail.
    df = pd.read_csv(path, dtype=str, keep_default_na=False, na_values=[""], encoding="utf-8")
    df["source_row_id"] = df["source_row_id"].astype(int)
    return df


def clean(raw: pd.DataFrame) -> tuple[pd.DataFrame, list[tuple[str, int]]]:
    log = [("Raw rows imported", len(raw))]

    # R5 exact duplicates across all 8 original columns, keep the first occurrence
    raw = raw.sort_values("source_row_id")
    dup_mask = raw.duplicated(subset=RAW_COLS, keep="first")
    log.append(("Exact duplicate lines excluded", int(dup_mask.sum())))
    df = raw.loc[~dup_mask].copy()

    # R2-R4 typing and trimming
    out = pd.DataFrame({"source_row_id": df["source_row_id"]})
    out["invoice_no"] = df["InvoiceNo"].str.strip()
    out["stock_code"] = df["StockCode"].str.strip().str.upper()
    desc = df["Description"].str.strip()
    out["description"] = desc.where(desc != "", None)
    out["quantity"] = df["Quantity"].str.strip().astype(int)
    out["invoice_datetime"] = pd.to_datetime(df["InvoiceDate"].str.strip(), format="%Y-%m-%d %H:%M:%S")
    out["invoice_date"] = out["invoice_datetime"].dt.date
    # Decimal keeps money exact (the SQL uses NUMERIC(10,3))
    out["unit_price"] = df["UnitPrice"].str.strip().map(Decimal)
    out["customer_id"] = pd.to_numeric(df["CustomerID"].str.strip(), errors="raise").astype("Int64")
    out["country"] = df["Country"].str.strip()
    out["line_revenue"] = [Decimal(q) * p for q, p in zip(out["quantity"], out["unit_price"])]

    # R8 classification (same order as the SQL CASE expression)
    is_service = out["stock_code"].isin(SERVICE_CODES) | out["stock_code"].str.startswith("GIFT_0001_")
    is_c = out["invoice_no"].str.startswith("C")
    is_a = out["invoice_no"].str.startswith("A")
    zero_price = out["unit_price"].map(lambda p: p == 0)
    ttype = pd.Series("Sale", index=out.index)
    ttype[zero_price] = "Zero Price"
    ttype[out["quantity"] <= 0] = "Stock Adjustment"
    ttype[is_service] = "Non-Product"
    ttype[is_a] = "Adjustment"
    ttype[is_c] = "Cancellation"
    out["transaction_type"] = ttype
    out["is_product"] = ~is_service
    out["is_cancellation"] = is_c
    out["has_customer_id"] = out["customer_id"].notna()

    log.append(("Rows in cleaned table", len(out)))
    for t in ["Sale", "Cancellation", "Non-Product", "Stock Adjustment", "Zero Price", "Adjustment"]:
        log.append((f"Classified as {t}", int((out["transaction_type"] == t).sum())))
    log.append(("Cleaned lines without CustomerID (kept)", int((~out["has_customer_id"]).sum())))
    log.append(("Cleaned lines without description (kept)", int(out["description"].isna().sum())))
    return out[OUT_COLS], log


def to_csv_frame(df: pd.DataFrame) -> pd.DataFrame:
    """Format values the same way PostgreSQL exports them (see 07/12 instructions)."""
    f = df.copy()
    f["invoice_datetime"] = f["invoice_datetime"].dt.strftime("%Y-%m-%d %H:%M:%S")
    f["invoice_date"] = f["invoice_date"].astype(str)
    f["unit_price"] = f["unit_price"].map(lambda d: f"{d:.3f}")
    # Decimal keeps the sign of zero (-1 x 0 = -0); PostgreSQL prints 0.000, so normalise it.
    f["line_revenue"] = f["line_revenue"].map(lambda d: f"{(d if d != 0 else Decimal(0)):.3f}")
    f["customer_id"] = f["customer_id"].astype("string")
    for b in ["is_product", "is_cancellation", "has_customer_id"]:
        f[b] = f[b].map({True: "true", False: "false"})
    return f.sort_values("source_row_id")


def compare(py: pd.DataFrame, sql_path: str) -> bool:
    sql = pd.read_csv(sql_path, dtype=str, keep_default_na=False, na_values=[""])
    sql = sql.sort_values("source_row_id", key=lambda s: s.astype(int)).reset_index(drop=True)
    py = py.astype("string").reset_index(drop=True)
    ok = True
    if len(sql) != len(py):
        print(f"ROW COUNT MISMATCH: SQL={len(sql)}  Python={len(py)}")
        return False
    for col in OUT_COLS:
        a = sql[col].fillna("<NULL>").astype(str)
        b = py[col].fillna("<NULL>").astype(str)
        diff = int((a != b).sum())
        print(f"  {col:<18} differences: {diff}")
        ok &= diff == 0
    return ok


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("raw_csv")
    ap.add_argument("out_csv")
    ap.add_argument("--compare", help="CSV exported from staging.clean_online_retail")
    a = ap.parse_args()

    cleaned, log = clean(load_raw(a.raw_csv))
    print("Cleaning log (Python):")
    for name, n in log:
        print(f"  {name:<45} {n:>9,}")
    sale = cleaned[cleaned["transaction_type"] == "Sale"]
    canc = cleaned[(cleaned["transaction_type"] == "Cancellation") & cleaned["is_product"]]
    total = sum(sale["line_revenue"], Decimal(0))
    cancelled = sum(canc["line_revenue"], Decimal(0))
    print(f"  Total Revenue (product sales)             £{total:,.2f}")
    print(f"  Product cancellations                     £{cancelled:,.2f}")
    print(f"  Net Revenue                               £{total + cancelled:,.2f}")

    frame = to_csv_frame(cleaned)
    frame.to_csv(a.out_csv, index=False, encoding="utf-8", lineterminator="\n")
    print(f"Written {len(frame):,} rows to {a.out_csv}")

    if a.compare:
        print("Parity check against SQL export:")
        same = compare(frame, a.compare)
        print("RESULT:", "IDENTICAL" if same else "DIFFERENCES FOUND")
        return 0 if same else 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
