-- ============================================================================
-- SCRIPT 01: DATA CLEANING & HYGIENE PIPELINE
-- Project: E-Commerce Customer Churn & RFM Segmentation Analysis
-- Dialect: SQLite 3.x (ANSI cross-database compatibility notes documented below)
-- Dataset: UCI Online Retail II (1,067,371 raw transactional rows, 2009-2011)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CRITICAL METHODOLOGICAL NOTES:
--
-- 1. Handling of Cancellations & Returns (Gross vs. Net Spend):
--    Filtering out `Quantity <= 0` and `Invoice LIKE 'C%'` removes cancelled
--    transactions and credit returns.
--    * Terminology: Throughout this project, `Monetary` represents HISTORICAL
--      GROSS PURCHASE VALUE, not Net Revenue.
--    * Analytical Rationale:
--      a) In the raw UCI dataset, return records ('C...') are unlinked (they
--         lack a relational foreign key pointing back to the original order).
--      b) Simple subtraction produces negative or zero net spend for 105
--         customers, which invalidates standard logarithmic and quartile RFM scoring.
--      c) Return timestamps distort Recency (a cancellation date does not
--         reflect positive customer purchase engagement or interest).
--      d) In production enterprise environments, return propensity is modeled as
--         a separate behavioral feature rather than subtracted naively.
--
-- 2. Deduplication Strategy & Record Impact Audit:
--    Identical order lines within the same invoice at the exact same timestamp
--    are identified and deduplicated using ROW_NUMBER().
--    * Audit Findings:
--      - Valid candidate rows before deduplication: 805,549.
--      - Rows after deduplication: 779,423.
--      - Exactly 26,126 duplicate records removed across 24,714 duplicate groups.
--      - 24,712 groups (99.99%) are 100% byte-for-byte identical across ALL fields.
--      - Exactly 2 groups had minor trailing whitespace differences in Description.
--    * Analytical Justification:
--      In retail data systems, multiple units of an item purchased together are
--      recorded in the `Quantity` field. Identical row repetitions with identical
--      timestamps represent data extraction and logging artifacts from the UCI
--      annual dataset concatenation. Deduplicating them prevents artificial
--      inflation of order quantities and customer spend.
-- ----------------------------------------------------------------------------

-- Step 1.1: Exploratory Quality Audit (Raw Data Hygiene Assessment)
SELECT 
    COUNT(*) AS total_raw_rows,
    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_customer_id_rows,
    SUM(CASE WHEN Quantity <= 0 THEN 1 ELSE 0 END) AS non_positive_qty_rows,
    SUM(CASE WHEN Price <= 0 THEN 1 ELSE 0 END) AS non_positive_price_rows,
    SUM(CASE WHEN Invoice LIKE 'C%' THEN 1 ELSE 0 END) AS cancellation_rows,
    SUM(CASE WHEN datetime(TRIM(InvoiceDate)) IS NULL THEN 1 ELSE 0 END) AS unparseable_dates
FROM raw_retail;

-- Step 1.2: Audit Duplicate Groups
-- Quantify identical transaction lines sharing the same invoice and item attributes:
SELECT 
    Invoice, 
    StockCode, 
    Quantity, 
    Price, 
    CAST(CustomerID AS INT) AS CustomerID, 
    datetime(TRIM(InvoiceDate)) AS InvoiceDate, 
    COUNT(*) AS duplicate_count
FROM raw_retail
WHERE CustomerID IS NOT NULL 
  AND Quantity > 0 
  AND Price > 0
  AND Invoice NOT LIKE 'C%'
GROUP BY Invoice, StockCode, Quantity, Price, CAST(CustomerID AS INT), datetime(TRIM(InvoiceDate))
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC
LIMIT 10;

-- Step 1.3: Build Cleaned Table with Deduplication
DROP TABLE IF EXISTS cleaned_retail;

CREATE TABLE cleaned_retail AS
WITH numbered_transactions AS (
    SELECT 
        Invoice,
        StockCode,
        Description,
        Quantity,
        datetime(TRIM(InvoiceDate)) AS InvoiceDate,
        Price,
        CAST(CustomerID AS INT) AS CustomerID,
        Country,
        ROW_NUMBER() OVER (
            PARTITION BY Invoice, StockCode, Quantity, Price, CAST(CustomerID AS INT), datetime(TRIM(InvoiceDate))
            ORDER BY Description
        ) AS row_num
    FROM raw_retail
    WHERE CustomerID IS NOT NULL
      AND Quantity > 0
      AND Price > 0
      AND Invoice NOT LIKE 'C%'
      AND datetime(TRIM(InvoiceDate)) IS NOT NULL
)
SELECT 
    Invoice,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    Price,
    CustomerID,
    Country
FROM numbered_transactions
WHERE row_num = 1;

-- Step 1.4: Validation Checks (Gatekeeper for Downstream Modeling)
SELECT 
    COUNT(*) AS total_cleaned_rows,
    COUNT(DISTINCT CustomerID) AS unique_customers,
    COUNT(DISTINCT Invoice) AS unique_invoices,
    MIN(InvoiceDate) AS earliest_valid_date,
    MAX(InvoiceDate) AS latest_valid_date,
    SUM(CASE WHEN CustomerID IS NULL THEN 1 ELSE 0 END) AS null_cust_check,
    SUM(CASE WHEN Quantity <= 0 THEN 1 ELSE 0 END) AS neg_qty_check,
    SUM(CASE WHEN Price <= 0 THEN 1 ELSE 0 END) AS neg_price_check,
    SUM(CASE WHEN datetime(InvoiceDate) IS NULL THEN 1 ELSE 0 END) AS bad_date_check
FROM cleaned_retail;

-- ----------------------------------------------------------------------------
-- ANSI CROSS-DATABASE COMPATIBILITY EQUIVALENTS:
-- ----------------------------------------------------------------------------
-- PostgreSQL:
--   CREATE TABLE cleaned_retail AS
--   WITH numbered AS (
--       SELECT Invoice, StockCode, Description, Quantity,
--              TO_TIMESTAMP(TRIM(InvoiceDate), 'YYYY-MM-DD HH24:MI:SS') AS InvoiceDate,
--              Price, CAST(CustomerID AS BIGINT) AS CustomerID, Country,
--              ROW_NUMBER() OVER (
--                  PARTITION BY Invoice, StockCode, Quantity, Price, CAST(CustomerID AS BIGINT), TRIM(InvoiceDate)
--                  ORDER BY Description
--              ) AS rn
--       FROM raw_retail
--       WHERE CustomerID IS NOT NULL AND Quantity > 0 AND Price > 0 AND Invoice NOT LIKE 'C%'
--   )
--   SELECT Invoice, StockCode, Description, Quantity, InvoiceDate, Price, CustomerID, Country
--   FROM numbered WHERE rn = 1;
-- ----------------------------------------------------------------------------
