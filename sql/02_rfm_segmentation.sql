-- ============================================================================
-- SCRIPT 02: RFM METRICS & DETERMINISTIC NTILE(4) QUARTILE SCORING
-- Project: E-Commerce Customer Churn & RFM Segmentation Analysis
-- Dialect: SQLite 3.x (ANSI cross-database compatibility notes documented below)
-- Target Reference Date: 2011-12-10 (Day following the final dataset transaction)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CRITICAL METHODOLOGICAL NOTES:
--
-- 1. Deterministic Customer Country Assignment (Issue B Resolution):
--    A small fraction of customers (13 accounts, 0.22%) recorded transactions
--    across multiple countries (e.g. cross-border relocation, multi-office shipping).
--    To ensure 100% deterministic, ANSI-compliant assignment without relying on
--    bare-column engine optimizations, we explicitly assign each customer to the
--    country of their MOST RECENT transaction:
--      ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY InvoiceDate DESC, Invoice DESC) = 1
--
-- 2. Date Arithmetic & Time Component Stripping:
--    In SQLite, `julianday('2011-12-10') - julianday(MAX(InvoiceDate))` produces
--    fractional decimals due to time components (e.g., 0.465 days).
--    Wrapping MAX(InvoiceDate) in `date()` ensures clean, discrete calendar-day recency:
--      CAST(ROUND(julianday('2011-12-10') - julianday(date(MAX(c.InvoiceDate)))) AS INT)
--
-- 3. NTILE(4) Quartile Scoring & Tie-Breaking Behavior (Issue C Analysis):
--    Standard NTILE(4) partitions a sorted population into 4 equal-sized buckets
--    (~1,470 customers each across 5,878 accounts).
--    When many customers share identical metric values (e.g., 1,623 single-order buyers),
--    NTILE() must split identical values across quartile boundaries:
--      - 1,470 single-order customers receive F_Score = 1
--      - 153 single-order customers receive F_Score = 2
--    Adding `, CustomerID ASC` as a secondary ORDER BY criterion enforces 100%
--    deterministic bucket assignments across database engines and runs.
--    Analytical Decision: We preserve this deterministic NTILE(4) approach for
--    standardized quartile segmentation, while accommodating single-order buyers
--    explicitly in downstream segment definitions (Script 03).
--
-- 4. Quartile Scoring Directions:
--    * R_Score (ORDER BY Recency DESC): Bucket 1 = Coldest (>380d), Bucket 4 = Freshest (1-26d).
--    * F_Score (ORDER BY Frequency ASC): Bucket 1 = 1 order, Bucket 4 = High frequency (7-398 orders).
--    * M_Score (ORDER BY Monetary ASC): Bucket 1 = Lowest spend, Bucket 4 = Top gross spenders.
-- ----------------------------------------------------------------------------

-- Step 2.1: RFM Aggregations and Scoring View
WITH customer_latest_country AS (
    -- Deterministic rule: assign customer to country of their most recent purchase
    SELECT CustomerID, Country
    FROM (
        SELECT 
            CustomerID, 
            Country,
            ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY InvoiceDate DESC, Invoice DESC) AS rn
        FROM cleaned_retail
    ) WHERE rn = 1
),
rfm_base AS (
    SELECT 
        c.CustomerID,
        l.Country,
        MIN(c.InvoiceDate) AS FirstPurchaseDate,
        MAX(c.InvoiceDate) AS LastPurchaseDate,
        CAST(ROUND(julianday('2011-12-10') - julianday(date(MAX(c.InvoiceDate)))) AS INT) AS Recency,
        COUNT(DISTINCT c.Invoice) AS Frequency,
        ROUND(SUM(c.Quantity * c.Price), 2) AS Monetary
    FROM cleaned_retail c
    JOIN customer_latest_country l ON c.CustomerID = l.CustomerID
    GROUP BY c.CustomerID, l.Country
),
rfm_scores AS (
    SELECT 
        CustomerID,
        Country,
        FirstPurchaseDate,
        LastPurchaseDate,
        Recency,
        Frequency,
        Monetary,
        ROUND(Monetary / Frequency, 2) AS AvgOrderValue,
        -- Deterministic Quartile Scoring (1 = Lowest/Worst, 4 = Highest/Best)
        NTILE(4) OVER (ORDER BY Recency DESC, CustomerID ASC) AS R_Score,
        NTILE(4) OVER (ORDER BY Frequency ASC, CustomerID ASC) AS F_Score,
        NTILE(4) OVER (ORDER BY Monetary ASC, CustomerID ASC) AS M_Score
    FROM rfm_base
)
SELECT 
    CustomerID,
    Country,
    FirstPurchaseDate,
    LastPurchaseDate,
    Recency,
    Frequency,
    Monetary AS HistoricalGrossPurchaseValue,
    AvgOrderValue,
    R_Score,
    F_Score,
    M_Score
FROM rfm_scores
ORDER BY Monetary DESC
LIMIT 20;

-- Step 2.2: Phase 2 Validation Queries (Quartile Balance & Boundary Verification)
WITH customer_latest_country AS (
    SELECT CustomerID, Country
    FROM (
        SELECT CustomerID, Country, ROW_NUMBER() OVER (PARTITION BY CustomerID ORDER BY InvoiceDate DESC, Invoice DESC) AS rn
        FROM cleaned_retail
    ) WHERE rn = 1
),
rfm_base AS (
    SELECT 
        c.CustomerID,
        CAST(ROUND(julianday('2011-12-10') - julianday(date(MAX(c.InvoiceDate)))) AS INT) AS Recency,
        COUNT(DISTINCT c.Invoice) AS Frequency,
        ROUND(SUM(c.Quantity * c.Price), 2) AS Monetary
    FROM cleaned_retail c
    JOIN customer_latest_country l ON c.CustomerID = l.CustomerID
    GROUP BY c.CustomerID, l.Country
),
rfm_scores AS (
    SELECT 
        CustomerID,
        Recency,
        Frequency,
        Monetary,
        NTILE(4) OVER (ORDER BY Recency DESC, CustomerID ASC) AS R_Score,
        NTILE(4) OVER (ORDER BY Frequency ASC, CustomerID ASC) AS F_Score,
        NTILE(4) OVER (ORDER BY Monetary ASC, CustomerID ASC) AS M_Score
    FROM rfm_base
)
SELECT 
    'R_Score' AS Metric, R_Score AS Quartile, COUNT(*) AS Customer_Count, 
    MIN(Recency) AS Min_Val, MAX(Recency) AS Max_Val, ROUND(AVG(Recency), 1) AS Avg_Val
FROM rfm_scores GROUP BY R_Score
UNION ALL
SELECT 
    'F_Score' AS Metric, F_Score AS Quartile, COUNT(*) AS Customer_Count, 
    MIN(Frequency) AS Min_Val, MAX(Frequency) AS Max_Val, ROUND(AVG(Frequency), 1) AS Avg_Val
FROM rfm_scores GROUP BY F_Score
UNION ALL
SELECT 
    'M_Score' AS Metric, M_Score AS Quartile, COUNT(*) AS Customer_Count, 
    MIN(Monetary) AS Min_Val, MAX(Monetary) AS Max_Val, ROUND(AVG(Monetary), 1) AS Avg_Val
FROM rfm_scores GROUP BY M_Score;

-- ----------------------------------------------------------------------------
-- ANSI CROSS-DATABASE RECENCY SYNTAX EQUIVALENTS:
-- ----------------------------------------------------------------------------
-- PostgreSQL:
--   ('2011-12-10'::date - MAX(InvoiceDate)::date) AS Recency
--
-- SQL Server (T-SQL):
--   DATEDIFF(day, CAST(MAX(InvoiceDate) AS DATE), '2011-12-10') AS Recency
--
-- MySQL:
--   DATEDIFF('2011-12-10', DATE(MAX(InvoiceDate))) AS Recency
-- ----------------------------------------------------------------------------
