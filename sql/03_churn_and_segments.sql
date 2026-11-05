-- ============================================================================
-- SCRIPT 03: CHURN DEFINITION & BEHAVIORAL CUSTOMER SEGMENTATION
-- Project: E-Commerce Customer Churn & RFM Segmentation Analysis
-- Dialect: SQLite 3.x (ANSI cross-database compatibility notes documented below)
-- Target Reference Date: 2011-12-10
-- ============================================================================

-- ----------------------------------------------------------------------------
-- CRITICAL METHODOLOGICAL NOTES:
--
-- 1. Churn Definition & Business Rationale:
--    In non-contractual e-commerce, customer attrition is unobserved (there is no
--    formal contract cancellation).
--    * Definition: For the purpose of this analysis, customers inactive for
--      more than 90 days as of 2011-12-10 are classified as churned:
--        CASE WHEN Recency > 90 THEN 1 ELSE 0 END AS IsChurned
--    * Analytical Framing: This threshold was selected as a practical business
--      assumption and proxy for non-contractual retail settings, aligning with
--      typical quarterly replenishment and marketing cycles. It is a historical
--      classification benchmark, not a predictive machine-learning output.
--
-- 2. Behavioral Customer Segmentation Hierarchy (Issue D Resolution):
--    The 6 behavioral segments are evaluated in strict priority order via CASE:
--    * Champions (R_Score = 4 AND F_Score = 4):
--      Top quartile recency and repeat frequency. Highest lifetime engagement.
--      Note: Champions classification depends strictly on R and F, not M_Score.
--    * New Customers (R_Score = 4 AND Frequency = 1):
--      Customers who placed their very first order within the last ~25 days.
--      Rule note: We explicitly use `Frequency = 1` rather than `F_Score = 1`
--      to ensure all recent first-time buyers are captured without arbitrary
--      exclusion caused by quartile tie-breaking.
--    * Loyal (R_Score >= 3 AND F_Score >= 3):
--      Consistent repeat buyers active within the last ~96 days.
--    * Potential (R_Score >= 3 AND F_Score <= 2):
--      Recent buyers with low historical order counts; prime candidates for cross-selling.
--    * Lost (R_Score = 1 AND F_Score <= 2):
--      Lapsed low-frequency customers inactive for >380 days. Lowest retention ROI.
--    * At Risk (All other customers via `ELSE 'At Risk'`):
--      Lapsed customers who previously purchased multiple times (specifically all
--      R_Score = 2 accounts, plus R_Score = 1 accounts with F_Score >= 3).
--      Represents the primary target for win-back campaigns (£2.73M Historical Gross Spend of At-Risk Customers).
--
-- 3. Deterministic Country Assignment:
--    Enforces the most recent transaction country per customer via `customer_latest_country`.
-- ----------------------------------------------------------------------------

DROP TABLE IF EXISTS customer_rfm_segments;

CREATE TABLE customer_rfm_segments AS
WITH customer_latest_country AS (
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
    Monetary,
    AvgOrderValue,
    R_Score,
    F_Score,
    M_Score,
    CAST((R_Score || F_Score || M_Score) AS INT) AS RFM_Combined,
    -- Churn Flag (Practical Retail Benchmark)
    CASE WHEN Recency > 90 THEN 1 ELSE 0 END AS IsChurned,
    CASE WHEN Recency > 90 THEN 'Churned' ELSE 'Retained' END AS ChurnStatus,
    -- Mutually Exclusive Behavioral Segmentation Hierarchy
    CASE 
        WHEN R_Score = 4 AND F_Score = 4 THEN 'Champions'
        WHEN R_Score = 4 AND Frequency = 1 THEN 'New Customers'
        WHEN R_Score >= 3 AND F_Score >= 3 THEN 'Loyal'
        WHEN R_Score >= 3 AND F_Score <= 2 THEN 'Potential'
        WHEN R_Score = 1 AND F_Score <= 2 THEN 'Lost'
        ELSE 'At Risk'
    END AS Segment
FROM rfm_scores;

-- Step 3.2: Phase 3 Validation Checks (Segment Breakdown & Health)
SELECT 
    Segment,
    COUNT(*) AS total_customers,
    SUM(IsChurned) AS churned_customers,
    ROUND(AVG(IsChurned) * 100.0, 2) AS churn_rate_pct,
    ROUND(AVG(Recency), 1) AS avg_recency_days,
    ROUND(AVG(Frequency), 1) AS avg_frequency_orders,
    ROUND(AVG(Monetary), 2) AS avg_monetary_spend,
    ROUND(SUM(Monetary), 2) AS total_segment_gross_value
FROM customer_rfm_segments
GROUP BY Segment
ORDER BY total_customers DESC;

-- Verification: Ensure 0 NULL segments and 100% customer coverage
SELECT 
    SUM(CASE WHEN Segment IS NULL THEN 1 ELSE 0 END) AS null_segment_count,
    SUM(CASE WHEN (Recency > 90 AND IsChurned != 1) OR (Recency <= 90 AND IsChurned != 0) THEN 1 ELSE 0 END) AS churn_flag_errors,
    COUNT(*) AS total_processed_customers
FROM customer_rfm_segments;

-- ----------------------------------------------------------------------------
-- ANSI CROSS-DATABASE STRING CONCATENATION:
-- ----------------------------------------------------------------------------
-- SQLite:      (R_Score || F_Score || M_Score)
-- PostgreSQL:  (R_Score::text || F_Score::text || M_Score::text)
-- SQL Server:  CONCAT(R_Score, F_Score, M_Score)
-- MySQL:       CONCAT(R_Score, F_Score, M_Score)
-- ----------------------------------------------------------------------------
