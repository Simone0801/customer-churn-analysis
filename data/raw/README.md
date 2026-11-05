# 📂 Raw Dataset Information

The raw transactional dataset (`online_retail_II.xlsx`, ~45.6 MB) is not included directly in this repository to keep repository clone sizes lightweight and adhere to version control best practices for large binary files.

---

## 📥 Dataset Source & Download Instructions

The original raw dataset is publicly available from the **UCI Machine Learning Repository**:

* **Dataset Name:** Online Retail II
* **Repository Link:** [UCI Machine Learning Repository — Online Retail II](https://archive.ics.uci.edu/dataset/502/online+retail+ii)
* **File Format:** Excel workbook (`online_retail_II.xlsx`) containing two sheets:
  * `Year 2009-2010` (525,461 rows)
  * `Year 2010-2011` (541,910 rows)
  * **Total Raw Transactions:** 1,067,371 rows

---

## 🛠️ Database Setup (Optional)

If you wish to re-execute data cleaning and RFM scoring directly from raw source data:

1. Download `online_retail_II.xlsx` from the [UCI repository link](https://archive.ics.uci.edu/dataset/502/online+retail+ii).
2. Place the file in this directory (`data/raw/online_retail_II.xlsx`).
3. Note that the standard SQLite CLI `.import` command accepts delimited text (CSV), not proprietary `.xlsx` workbooks. Export both workbook sheets (`Year 2009-2010` and `Year 2010-2011`) to CSV, concatenate them (preserving the header once), and import into SQLite table `raw_retail` (or import directly via DB Browser for SQLite / DBeaver table import wizard).
4. Run the SQL pipeline scripts located in the [`sql/`](../../sql/) directory in sequence (`01_data_cleaning.sql` through `04_analysis_queries.sql`).

> [!NOTE]
> **Reproducibility:** You do **not** need to download the raw Excel file to view or evaluate the project. All fully validated, cleaned, and segmented customer data is already provided in [`data/processed/customer_churn_rfm.csv`](../processed/customer_churn_rfm.csv) and is pre-embedded inside [`power_bi/Customer_Churn_Analysis.pbix`](../../power_bi/Customer_Churn_Analysis.pbix).
