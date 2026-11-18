# Source information

| Item | Detail |
|---|---|
| Dataset | **Online Retail** |
| Repository | UCI Machine Learning Repository, dataset id 352 |
| Page | https://archive.ics.uci.edu/dataset/352/online+retail |
| DOI | https://doi.org/10.24432/C5BW33 |
| Creator | Daqing Chen, School of Engineering, London South Bank University |
| Donated to UCI | 5 November 2015 |
| Licence | Creative Commons Attribution 4.0 International (CC BY 4.0) |
| Size | 541,909 instances, 8 columns |
| Period | 1 December 2010 08:26 – 9 December 2011 12:50 |
| Currency | GBP (sterling) |

## Description (paraphrased from UCI)

A transnational data set containing all transactions of a UK-based, registered, non-store online retailer selling unique all-occasion gifts. Many of the company's customers are wholesalers. Invoice numbers starting with the letter "c" indicate a cancellation.

## Variables (UCI definitions)

| Variable | Definition |
|---|---|
| InvoiceNo | 6-digit number uniquely assigned to each transaction; starts with 'c' for a cancellation |
| StockCode | 5-digit number uniquely assigned to each distinct product |
| Description | Product name |
| Quantity | Quantity of each product per transaction |
| InvoiceDate | Day and time when the transaction was generated |
| UnitPrice | Price per unit in sterling |
| CustomerID | 5-digit number uniquely assigned to each customer |
| Country | Country where the customer resides |

Observed in the data (documented in `Documentation/05_Data_Quality_Report.docx`): some stock codes are service codes (POST, M, D, AMAZONFEE, …), 3 invoices start with "A" (bad-debt adjustments), and 135,080 lines have no CustomerID.

## Citation

Chen, D. (2015). *Online Retail* [Dataset]. UCI Machine Learning Repository. https://doi.org/10.24432/C5BW33

Introductory paper: Chen, D., Sain, S. L. and Guo, K. (2012). Data mining for the online retail industry: A case study of RFM model-based customer segmentation using data mining. *Journal of Database Marketing and Customer Strategy Management*, 19(3).

## Redistribution in this project

The licence (CC BY 4.0) permits sharing and adaptation with attribution. The project ZIP therefore includes:

- `raw/online_retail_raw.csv` - the official xlsx converted to CSV, values unchanged, plus a `source_row_id` lineage column;
- `cleaned/09_Cleaned_Online_Retail.csv` - the cleaned derivative produced by this project.

Changes made in the cleaned file are listed in `Documentation/06_Data_Cleaning_Methodology.docx`. The `.gitignore` keeps both CSVs out of the GitHub repository because of file size; the repository instead points to the official download (`download_instructions.md`).

This project is independent. It is not affiliated with, endorsed by, or an engagement with the retailer, UCI or the dataset creator.
