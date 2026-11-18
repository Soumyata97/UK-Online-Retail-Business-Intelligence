"""
UK Online Retail Sales & Customer Analytics
verify_kpis_and_rfm.py

Independent pandas re-calculation of the headline KPIs (query Q01) and of the RFM
segmentation (17_RFM_Analysis.sql) from the cleaned CSV. Prints both and, if the
SQL reference outputs are present, compares them. Used as a cross-check that SQL
and Python give the same business results.

Usage (from the project folder):
    python Python\\verify_kpis_and_rfm.py Dataset\\cleaned\\09_Cleaned_Online_Retail.csv
"""
import sys
from decimal import Decimal
from pathlib import Path

import numpy as np
import pandas as pd

REFERENCE_DATE = pd.Timestamp("2011-12-10")


def main(path: str) -> int:
    df = pd.read_csv(path, dtype={"invoice_no": str, "stock_code": str, "customer_id": "Int64"},
                     converters={"line_revenue": Decimal}, parse_dates=["invoice_datetime"])
    df["is_product"] = df["is_product"].astype(str).str.lower().eq("true")

    sale = df[df.transaction_type == "Sale"]
    pcanc = df[(df.transaction_type == "Cancellation") & df.is_product]
    total = sum(sale.line_revenue, Decimal(0))
    canc = sum(pcanc.line_revenue, Decimal(0))
    orders = sale.invoice_no.nunique()
    kpi = {
        "total_revenue": round(total, 2),
        "product_cancellations": round(canc, 2),
        "net_revenue": round(total + canc, 2),
        "orders": orders,
        "customers": sale.customer_id.dropna().nunique(),
        "units_sold": int(sale.quantity.sum()),
        "average_order_value": round(total / orders, 2),
    }
    print("Headline KPIs (Python):")
    for k, v in kpi.items():
        print(f"  {k:<24} {v}")

    # ---- RFM (same rules as 17_RFM_Analysis.sql) ----
    known = pd.concat([sale, pcanc])
    known = known[known.customer_id.notna()]
    g = known.groupby("customer_id")
    s = sale[sale.customer_id.notna()].groupby("customer_id")
    rfm = pd.DataFrame({
        "last_purchase": s.invoice_datetime.max().dt.normalize(),
        "frequency": s.invoice_no.nunique(),
    })
    rfm["monetary"] = g.line_revenue.apply(lambda x: round(sum(x, Decimal(0)), 2)).reindex(rfm.index)
    rfm["recency_days"] = (REFERENCE_DATE - rfm.last_purchase).dt.days
    scored = rfm[rfm.monetary > 0].copy()
    # CUME_DIST = rank(method="max", pct=True); CEIL(cume_dist * 5)
    scored["r"] = np.ceil((-scored.recency_days).rank(method="max", pct=True) * 5).astype(int)
    scored["f"] = np.ceil(scored.frequency.rank(method="max", pct=True) * 5).astype(int)
    scored["m"] = np.ceil(scored.monetary.astype(float).rank(method="max", pct=True) * 5).astype(int)
    scored["fm"] = (scored.f + scored.m + 1) // 2

    def segment(row) -> str:
        if row.r >= 4 and row.fm >= 4:
            return "Champions"
        if row.r >= 3 and row.fm >= 3:
            return "Loyal Customers"
        if row.r >= 4 and row.frequency == 1:
            return "New Customers"
        if row.r >= 3:
            return "Potential Loyalists"
        if row.r <= 2 and row.fm >= 3:
            return "At Risk"
        return "Hibernating"

    scored["segment"] = scored.apply(segment, axis=1)
    counts = scored.segment.value_counts()
    counts["Not Scored (net revenue <= 0)"] = int((rfm.monetary <= 0).sum())
    print("RFM segment counts (Python):")
    for k, v in counts.items():
        print(f"  {k:<32} {v}")

    ref = Path(path).resolve().parents[2] / "Analysis_Outputs" / "rfm_segment_summary.csv"
    if ref.exists():
        sql = pd.read_csv(ref).set_index("rfm_segment")["customers"]
        same = all(int(sql.get(k, -1)) == int(v) for k, v in counts.items())
        print("Comparison with SQL segment summary:", "IDENTICAL" if same else "DIFFERENT")
        return 0 if same else 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else "Dataset/cleaned/09_Cleaned_Online_Retail.csv"))
