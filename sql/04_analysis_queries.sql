-- ============================================================================
-- SCRIPT 04: EXECUTIVE BUSINESS ANALYSIS QUERIES
-- Project: E-Commerce Customer Churn & RFM Segmentation Analysis
-- Dialect: SQLite 3.x
-- Purpose: Extract executive insights on customer churn, historical gross purchase value exposure, and geography
-- Source Table: customer_rfm_segments (Generated in Script 03)
-- ============================================================================

-- Query 1: Overall Customer Base Health & Churn Rate
-- Output File: query1_overall_churn.csv
SELECT 
    COUNT(*) AS total_customers,
    SUM(IsChurned) AS total_churned,
    COUNT(*) - SUM(IsChurned) AS total_retained,
    ROUND(SUM(IsChurned) * 100.0 / COUNT(*), 2) AS overall_churn_rate_pct,
    ROUND((COUNT(*) - SUM(IsChurned)) * 100.0 / COUNT(*), 2) AS overall_retention_rate_pct
FROM customer_rfm_segments;

-- Query 2: Churn Vulnerability & Historical Gross Spend Exposure by Customer Segment
-- Output File: query2_churn_by_segment.csv
SELECT 
    Segment,
    COUNT(*) AS total_customers,
    SUM(IsChurned) AS churned_customers,
    ROUND(AVG(IsChurned) * 100.0, 2) AS churn_rate_pct,
    ROUND(SUM(Monetary), 2) AS total_segment_gross_value,
    ROUND(SUM(Monetary) * 100.0 / (SELECT SUM(Monetary) FROM customer_rfm_segments), 2) AS pct_of_total_gross_value
FROM customer_rfm_segments
GROUP BY Segment
ORDER BY churn_rate_pct DESC, total_customers DESC;

-- Query 3: Cohort Comparison — Churned vs. Retained Customer RFM Metrics
-- Output File: query3_churned_vs_retained_rfm.csv
SELECT 
    ChurnStatus,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customer_rfm_segments), 2) AS customer_share_pct,
    ROUND(AVG(Recency), 1) AS avg_recency_days,
    ROUND(AVG(Frequency), 1) AS avg_frequency_orders,
    ROUND(AVG(Monetary), 2) AS avg_monetary_spend,
    ROUND(AVG(AvgOrderValue), 2) AS avg_order_value,
    ROUND(SUM(Monetary), 2) AS total_gross_value_generated,
    ROUND(SUM(Monetary) * 100.0 / (SELECT SUM(Monetary) FROM customer_rfm_segments), 2) AS gross_value_share_pct
FROM customer_rfm_segments
GROUP BY ChurnStatus;

-- Query 4: Geographic Churn Distribution (Countries with >= 20 Accounts)
-- Output File: query4_top_countries_churn.csv
SELECT 
    Country,
    COUNT(*) AS total_customers,
    SUM(IsChurned) AS churned_customers,
    ROUND(SUM(IsChurned) * 100.0 / COUNT(*), 2) AS churn_rate_pct,
    ROUND(SUM(Monetary), 2) AS total_gross_value
FROM customer_rfm_segments
GROUP BY Country
HAVING COUNT(*) >= 20
ORDER BY churn_rate_pct DESC, total_customers DESC
LIMIT 10;
