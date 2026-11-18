# 24 · DAX Measures Library

**Project:** UK Online Retail Sales & Customer Analytics  
**Model:** `FactSales` + `DimDate`, `DimProduct`, `DimCustomer`, `DimCountry` (built by `21_Power_Query_M_Code.txt`)  
**Status:** Generated but **untested in Power BI** (Power BI Desktop is not available in the build environment). The "Expected (whole period)" values were produced by the equivalent SQL queries on PostgreSQL 16.15. After you create each measure, put it on a Card visual with no filters and compare it with the expected value. Record the result in `Testing/26_Data_Validation_Test_Cases.xlsx`.

---

## How to add these measures

1. **Create a measures table:** Home → *Enter data* → leave one empty column → name the table `_Measures` → *Load*. (A dedicated table keeps all measures in one place at the top of the Data pane.)
2. Select `_Measures` in the Data pane → Table tools → **New measure**.
3. Paste one measure (everything from the measure name to the end of its formula) into the formula bar → press **Enter**.
4. With the measure selected, set its format in Measure tools (Format, decimal places), as listed under each measure.
5. When all measures exist, delete the empty `Column1` from `_Measures` (the table icon changes to a calculator icon).

Folders (optional): select a measure → Properties pane → *Display folder* → type `1 Core`, `2 Time`, `3 Customer & Product`.

### Shared business definitions (identical to SQL)

| Term | Rule |
|---|---|
| Sale line | `TransactionType = "Sale"` (merchandise, quantity > 0, price > 0, not a C invoice) |
| Product cancellation | `TransactionType = "Cancellation"` and `IsProduct = TRUE` |
| Order | distinct `InvoiceNo` that has a Sale line |
| Customer metrics | only `CustomerKey <> 0` (key 0 = no CustomerID in the source) |

> **Filter behaviour to know:** these measures put a filter on `FactSales[TransactionType]` inside `CALCULATE`. That filter *replaces* any slicer on the same column. The dashboard slices by `CancellationStatus` instead, which works as expected: choosing **Cancelled** makes Total Revenue blank (there are no sales on cancellation invoices) and shows the cancellation measures; choosing **Not Cancelled** shows sales and zero cancellations.

---

## 1 · Core KPIs

### Total Revenue
```DAX
Total Revenue =
CALCULATE (
    SUM ( FactSales[LineRevenue] ),
    FactSales[TransactionType] = "Sale"
)
```
Format: Currency £, 2 decimals · **Expected: £10,247,219.32**  
Gross product sales. `CALCULATE` evaluates `SUM` in a filter context where only Sale lines remain.

### Product Cancellations
```DAX
Product Cancellations =
CALCULATE (
    SUM ( FactSales[LineRevenue] ),
    FactSales[TransactionType] = "Cancellation",
    FactSales[IsProduct] = TRUE ()
)
```
Format: Currency £, 2 decimals · **Expected: −£475,901.16**  
Negative value of merchandise lines on C invoices. Two filter arguments are combined with AND.

### Net Revenue
```DAX
Net Revenue = [Total Revenue] + [Product Cancellations]
```
Format: Currency £, 2 decimals · **Expected: £9,771,318.16**  
Methodology: sales retained after merchandise cancellations. Non-product cancellations (postage, Amazon fees, manual adjustments) are excluded because they are not product revenue. Cancellations cannot be matched to their original orders in the source, so a cancellation is counted in the month it was issued. If one of the two measures is blank in a context, `+` treats BLANK as 0.

### Gross Positive Sales
```DAX
Gross Positive Sales =
CALCULATE (
    SUM ( FactSales[LineRevenue] ),
    FactSales[CancellationStatus] = "Not Cancelled",
    FactSales[TransactionType] IN { "Sale", "Non-Product" },
    FactSales[LineRevenue] > 0
)
```
Format: Currency £ · **Expected: £10,631,048.74**  
Everything invoiced with a positive value, including postage and other charges.

### Total Orders
```DAX
Total Orders =
CALCULATE (
    DISTINCTCOUNT ( FactSales[InvoiceNo] ),
    FactSales[TransactionType] = "Sale"
)
```
Format: Whole number, thousands separator · **Expected: 19,773**

### Total Customers
```DAX
Total Customers =
CALCULATE (
    DISTINCTCOUNT ( FactSales[CustomerKey] ),
    FactSales[TransactionType] = "Sale",
    FactSales[CustomerKey] <> 0
)
```
Format: Whole number · **Expected: 4,334**  
Counts customers who bought in the current filter context. Key 0 (no CustomerID) is excluded so it is never counted as "one customer".

### Total Quantity Sold
```DAX
Total Quantity Sold =
CALCULATE (
    SUM ( FactSales[Quantity] ),
    FactSales[TransactionType] = "Sale"
)
```
Format: Whole number · **Expected: 5,561,387** (displayed as "Units Sold")

### Average Order Value
```DAX
Average Order Value = DIVIDE ( [Total Revenue], [Total Orders] )
```
Format: Currency £, 2 decimals · **Expected: £518.24**  
`DIVIDE` returns BLANK instead of an error when there are no orders.

### Average Selling Price
```DAX
Average Selling Price = DIVIDE ( [Total Revenue], [Total Quantity Sold] )
```
Format: Currency £, 4 decimals · **Expected: £1.8426**  
Revenue-weighted average price per unit.

### Revenue per Customer
```DAX
Revenue per Customer =
DIVIDE (
    CALCULATE ( [Total Revenue], FactSales[CustomerKey] <> 0 ),
    [Total Customers]
)
```
Format: Currency £, 2 decimals · **Expected: £2,015.97**  
Only revenue that belongs to identified customers is divided by the number of identified customers (otherwise the £1.51m with no CustomerID would inflate the result).

### Cancellation Invoice Count
```DAX
Cancellation Invoice Count =
CALCULATE (
    DISTINCTCOUNT ( FactSales[InvoiceNo] ),
    FactSales[TransactionType] = "Cancellation"
)
```
Format: Whole number · **Expected: 3,836**

### Cancellation Rate
```DAX
Cancellation Rate =
DIVIDE (
    [Cancellation Invoice Count],
    [Total Orders] + [Cancellation Invoice Count]
)
```
Format: Percentage, 1 decimal · **Expected: 16.2%**  
Share of all customer invoices (orders + cancellation invoices) that are cancellations.

### Value Cancellation Rate
```DAX
Value Cancellation Rate = DIVIDE ( - [Product Cancellations], [Total Revenue] )
```
Format: Percentage, 1 decimal · **Expected: 4.6%**

---

## 2 · Time intelligence

Requirements: `DimDate` is marked as a date table (Table tools → *Mark as date table* → column `Date`) and related to `FactSales[InvoiceDate]`.

> **Limited date range:** the data covers 1 Dec 2010 – 9 Dec 2011 only. Month-over-month works for Jan–Dec 2011. A **like-for-like** year-over-year comparison exists only for 1–9 December (2011 vs 2010). The YoY measures below deliberately return BLANK for any period whose prior-year period is not fully covered by data, so the dashboard never shows a misleading full-year comparison.

### Previous Month Revenue
```DAX
Previous Month Revenue =
CALCULATE ( [Total Revenue], DATEADD ( DimDate[Date], -1, MONTH ) )
```
Format: Currency £ · **Expected for 2011-11: £1,103,314.25** (October 2011)  
`DATEADD` shifts the dates currently in the filter context back one month.

### MoM Growth %
```DAX
MoM Growth % =
VAR CurrentRevenue = [Total Revenue]
VAR PreviousRevenue = [Previous Month Revenue]
RETURN
    IF (
        NOT ISBLANK ( PreviousRevenue ) && NOT ISBLANK ( CurrentRevenue ),
        DIVIDE ( CurrentRevenue - PreviousRevenue, PreviousRevenue )
    )
```
Format: Percentage, 1 decimal · **Expected for 2011-11: 31.6%** · for 2011-12: −57.7% (December 2011 has only 9 days - say so wherever it is shown)

### Previous Year Revenue (Comparable)
```DAX
Previous Year Revenue (Comparable) =
VAR FirstDataDate = CALCULATE ( MIN ( FactSales[InvoiceDate] ), REMOVEFILTERS () )
VAR LastDataDate  = CALCULATE ( MAX ( FactSales[InvoiceDate] ), REMOVEFILTERS () )
VAR CurrentDates  = FILTER ( VALUES ( DimDate[Date] ), DimDate[Date] <= LastDataDate )
VAR PriorDates    = SAMEPERIODLASTYEAR ( CurrentDates )
VAR PriorStart    = MINX ( PriorDates, DimDate[Date] )
RETURN
    IF ( PriorStart >= FirstDataDate, CALCULATE ( [Total Revenue], PriorDates ) )
```
Format: Currency £  
**Expected for December 2011: £408,004.93** (= 1–9 Dec 2010, because December 2011 ends on the 9th). **Expected for the year 2011: BLANK** (Jan–Nov 2010 do not exist in the data).  
Only dates that have data in the current year are shifted back a year, and the result is shown only when the whole prior period is inside the data range.

### YoY Growth %
```DAX
YoY Growth % =
VAR PriorRevenue = [Previous Year Revenue (Comparable)]
RETURN
    IF ( NOT ISBLANK ( PriorRevenue ), DIVIDE ( [Total Revenue] - PriorRevenue, PriorRevenue ) )
```
Format: Percentage, 1 decimal · **Expected for December 2011: 50.6%** (£614,490.92 vs £408,004.93). Caution: 9 December 2011 includes order 581483 (£168,469.60), which was cancelled 12 minutes later; on Net Revenue the comparison is very different. Treat this single 9-day comparison as illustrative only.

### YTD Revenue
```DAX
YTD Revenue =
CALCULATE ( [Total Revenue], DATESYTD ( DimDate[Date] ) )
```
Format: Currency £ · **Expected at 2011-12: £9,471,580.96** (1 Jan – 9 Dec 2011) · at 2010-12: £775,638.36  
`DATESYTD` returns all dates from 1 January of the year in context up to the last date in context.

### Running Total Revenue
```DAX
Running Total Revenue =
VAR LastVisibleDate = MAX ( DimDate[Date] )
RETURN
    CALCULATE (
        [Total Revenue],
        FILTER ( ALLSELECTED ( DimDate ), DimDate[Date] <= LastVisibleDate )
    )
```
Format: Currency £ · **Expected at 2011-11 (no slicers): £9,632,728.40**; at 2011-12: £10,247,219.32  
Unlike YTD it does not restart in January. `ALLSELECTED` keeps the date-range slicer's start date, so the running total starts at the first selected date. The whole `DimDate` table is cleared (not only the Date column) so it also works when the axis is `YearMonth`.

---

## 3 · Customer and product measures

### Top Customer Revenue
```DAX
Top Customer Revenue =
MAXX (
    FILTER ( VALUES ( DimCustomer[CustomerKey] ), DimCustomer[CustomerKey] <> 0 ),
    [Net Revenue]
)
```
Format: Currency £ · **Expected: £278,778.02** (customer 14646, Netherlands)  
Iterates the customers visible in context and returns the highest net revenue of a single customer. Calling a measure inside an iterator triggers **context transition** (each row becomes a filter).

### Customer Rank
```DAX
Customer Rank =
IF (
    HASONEVALUE ( DimCustomer[CustomerKey] )
        && SELECTEDVALUE ( DimCustomer[CustomerKey] ) <> 0,
    RANKX (
        FILTER ( ALLSELECTED ( DimCustomer ), DimCustomer[CustomerKey] <> 0 ),
        [Net Revenue], , DESC, SKIP
    )
)
```
Format: Whole number · **Expected: customer 14646 = 1, 18102 = 2, 17450 = 3** (matches SQL Q16)  
Ranks over whole rows of `DimCustomer`, so it works whether the table visual shows CustomerID, Customer or PrimaryCountry next to it. Returns BLANK on total rows and for the Unknown member.

### Product Rank
```DAX
Product Rank =
IF (
    HASONEVALUE ( DimProduct[ProductKey] ),
    RANKX ( ALLSELECTED ( DimProduct ), [Net Revenue], , DESC, SKIP )
)
```
Format: Whole number · **Expected: 22423 REGENCY CAKESTAND 3 TIER = 1, 85123A = 2, 47566 = 3** (matches SQL Q09)  
Uses Net Revenue so that orders cancelled within minutes (581483, 541431) do not create false top products. Service codes have blank Net Revenue and fall to the bottom.

### Customer Purchase Frequency
```DAX
Customer Purchase Frequency =
DIVIDE (
    CALCULATE ( [Total Orders], FactSales[CustomerKey] <> 0 ),
    [Total Customers]
)
```
Format: Decimal, 2 places · **Expected: 4.25** orders per customer (median is 2 - see SQL Q17)

### Repeat Customer Count
```DAX
Repeat Customer Count =
COUNTROWS (
    FILTER (
        VALUES ( DimCustomer[CustomerKey] ),
        DimCustomer[CustomerKey] <> 0
            && [Total Orders] > 1
    )
)
```
Format: Whole number · **Expected: 2,829**

### Repeat Customer Rate
```DAX
Repeat Customer Rate = DIVIDE ( [Repeat Customer Count], [Total Customers] )
```
Format: Percentage, 1 decimal · **Expected: 65.3%**

### Customer Segment Count
```DAX
Customer Segment Count =
CALCULATE (
    COUNTROWS ( DimCustomer ),
    DimCustomer[CustomerKey] <> 0,
    NOT ( ISBLANK ( DimCustomer[RScore] ) )
)
```
Format: Whole number · **Expected by segment:** Champions 1,233 · Loyal Customers 879 · New Customers 201 · Potential Loyalists 291 · At Risk 877 · Hibernating 839 (total 4,320 scored customers)  
Counts scored customers in the customer dimension. RFM is a **snapshot at 2011-12-10**: the segments do not change when you move the date slicer. Use `[Total Customers]` instead if you want "customers in this segment who bought in the selected period".

### Segment Revenue Share
```DAX
Segment Revenue Share =
DIVIDE (
    [Net Revenue],
    CALCULATE ( [Net Revenue], REMOVEFILTERS ( DimCustomer[CustomerSegment] ), DimCustomer[CustomerKey] <> 0 )
)
```
Format: Percentage, 1 decimal · **Expected for Champions: 70.5%** (£5,827,227.65 ÷ £8,265,476.93)  
The denominator is the net revenue of **all** identified customers (£8,265,476.93). It is slightly lower than the RFM-table total (£8,269,399.91) because it also includes the cancellations of the 38 customers who only have cancellation lines ("No purchases in period"). Both give 70.5% for Champions.

---

## Concepts used (short reference)

| Concept | Meaning in this library |
|---|---|
| Measure vs calculated column | Measures are calculated at query time for the current filter context (every KPI here). Calculated columns are computed once per row at refresh and stored; none are needed because row-level logic is done in SQL/Power Query. |
| Filter context | The set of filters from slicers, visual axes and rows that applies when a measure is evaluated. |
| Row context | "The current row" inside an iterator such as `FILTER`, `MAXX`, `SUMX`. It does not filter anything by itself. |
| `CALCULATE` | Evaluates an expression in a modified filter context (adds/replaces filters). Also turns row context into filter context (context transition). |
| `FILTER` | Returns the rows of a table that satisfy a condition; used inside `CALCULATE`, `COUNTROWS`, `RANKX`. |
| `DIVIDE` | Safe division; returns BLANK (or an alternative) instead of an error when the denominator is 0/BLANK. |
| `SUMX` | Iterates a table and sums an expression per row, e.g. `SUMX ( FactSales, FactSales[Quantity] * FactSales[UnitPrice] )` - equals `SUM ( FactSales[LineRevenue] )` here because LineRevenue is pre-calculated. |
| `DISTINCTCOUNT` | Number of distinct values (orders, customers). |
| `DATEADD` | Shifts the dates in context by a number of days/months/quarters/years. |
| `DATESYTD` | Dates from the start of the year to the last date in context. |
| `RANKX` | Position of the current item's value within a table of items. |

> Optional check of `SUMX`: create `Revenue (SUMX check) = CALCULATE ( SUMX ( FactSales, FactSales[Quantity] * FactSales[UnitPrice] ), FactSales[TransactionType] = "Sale" )`. It must equal `[Total Revenue]` exactly.
