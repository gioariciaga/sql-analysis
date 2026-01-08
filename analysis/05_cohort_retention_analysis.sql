/*
=============================================================================
COHORT RETENTION ANALYSIS
=============================================================================

PURPOSE:
Analyze customer retention and engagement patterns by signup cohort to
understand which customer groups are most successful and identify
opportunities for improvement.

BUSINESS VALUE:
- Validates product-market fit by cohort
- Measures impact of onboarding and feature improvements
- Identifies which acquisition channels/periods produce best customers
- Forecasts revenue retention for financial planning
- Guides investment decisions in customer segments

METHODOLOGY:
Groups customers by signup month (cohort) and tracks:
1. Retention rate: % of cohort still active
2. Revenue retention: MRR retained vs. starting MRR
3. Engagement patterns: Usage levels by customer age
4. Expansion behavior: Upgrade rates by cohort
5. Churn timing: When cohorts typically churn

OUTPUTS:
- Retention rates by cohort and age
- Revenue trends by cohort
- Engagement metrics over customer lifetime
- Cohort quality comparison
=============================================================================
*/

-- Define base cohorts with starting characteristics
WITH cohort_base AS (
    SELECT 
        customer_id,
        company_name,
        DATE_TRUNC('month', signup_date) as cohort_month,
        signup_date,
        plan_type as starting_plan,
        industry,
        status
    FROM customers
),

-- Calculate cohort sizes and starting state
cohort_starting_metrics AS (
    SELECT 
        cohort_month,
        COUNT(*) as cohort_size,
        COUNT(CASE WHEN starting_plan = 'Starter' THEN 1 END) as starter_count,
        COUNT(CASE WHEN starting_plan = 'Professional' THEN 1 END) as professional_count,
        COUNT(CASE WHEN starting_plan = 'Enterprise' THEN 1 END) as enterprise_count,
        
        -- Initial revenue (using first recorded MRR as proxy)
        SUM(c.mrr) as starting_mrr,
        AVG(c.mrr) as avg_starting_mrr
    FROM cohort_base cb
    JOIN customers c ON cb.customer_id = c.customer_id
    GROUP BY cohort_month
),

-- Calculate current retention and status
cohort_current_status AS (
    SELECT 
        cb.cohort_month,
        
        -- Customer retention
        COUNT(CASE WHEN cb.status = 'Active' THEN 1 END) as active_customers,
        COUNT(CASE WHEN cb.status = 'At Risk' THEN 1 END) as at_risk_customers,
        COUNT(CASE WHEN cb.status = 'Churned' THEN 1 END) as churned_customers,
        
        -- Revenue retention
        SUM(c.mrr) as current_mrr,
        SUM(CASE WHEN cb.status = 'Active' THEN c.mrr ELSE 0 END) as active_mrr,
        
        -- Plan evolution
        COUNT(CASE 
            WHEN cb.starting_plan = 'Starter' AND c.plan_type = 'Professional' THEN 1 
        END) as starter_to_pro_upgrades,
        COUNT(CASE 
            WHEN cb.starting_plan = 'Professional' AND c.plan_type = 'Enterprise' THEN 1 
        END) as pro_to_enterprise_upgrades
        
    FROM cohort_base cb
    JOIN customers c ON cb.customer_id = c.customer_id
    GROUP BY cb.cohort_month
),

-- Calculate average engagement by cohort (last 30 days)
cohort_engagement AS (
    SELECT 
        cb.cohort_month,
        AVG(ca.logins_count) as avg_logins,
        AVG(ca.feature_usage_score) as avg_usage_score,
        AVG(ca.nps_score) as avg_nps,
        SUM(ca.support_tickets_opened) as total_tickets
    FROM cohort_base cb
    JOIN customer_activity ca ON cb.customer_id = ca.customer_id
    WHERE ca.activity_date >= CURRENT_DATE - INTERVAL '30 days'
      AND cb.status = 'Active'  -- Only measure active customers
    GROUP BY cb.cohort_month
),

-- Calculate months since signup for age-based analysis
cohort_age AS (
    SELECT 
        cb.cohort_month,
        EXTRACT(MONTH FROM AGE(CURRENT_DATE, cb.cohort_month)) as cohort_age_months
    FROM cohort_base cb
    GROUP BY cb.cohort_month
)

-- Final cohort analysis output
SELECT 
    csm.cohort_month,
    ca.cohort_age_months,
    
    -- Cohort size and composition
    csm.cohort_size,
    csm.starter_count,
    csm.professional_count,
    csm.enterprise_count,
    
    -- Customer retention metrics
    ccs.active_customers,
    ROUND(100.0 * ccs.active_customers / csm.cohort_size, 1) as customer_retention_rate,
    ccs.at_risk_customers,
    ROUND(100.0 * ccs.at_risk_customers / csm.cohort_size, 1) as at_risk_rate,
    ccs.churned_customers,
    ROUND(100.0 * ccs.churned_customers / csm.cohort_size, 1) as churn_rate,
    
    -- Revenue retention metrics
    ROUND(csm.starting_mrr, 2) as starting_mrr,
    ROUND(ccs.current_mrr, 2) as current_mrr,
    ROUND(100.0 * ccs.current_mrr / csm.starting_mrr, 1) as revenue_retention_rate,
    ROUND(ccs.current_mrr - csm.starting_mrr, 2) as net_mrr_change,
    
    -- Expansion metrics
    ccs.starter_to_pro_upgrades,
    ccs.pro_to_enterprise_upgrades,
    ROUND(100.0 * (ccs.starter_to_pro_upgrades + ccs.pro_to_enterprise_upgrades) / csm.cohort_size, 1) as upgrade_rate,
    
    -- Engagement metrics (current active customers only)
    ROUND(ce.avg_logins, 1) as avg_weekly_logins,
    ROUND(ce.avg_usage_score, 1) as avg_usage_score,
    ROUND(ce.avg_nps, 1) as avg_nps,
    ce.total_tickets as total_support_tickets_30d,
    
    -- Per-customer averages
    ROUND(csm.avg_starting_mrr, 2) as avg_starting_mrr_per_customer,
    ROUND(ccs.active_mrr / NULLIF(ccs.active_customers, 0), 2) as avg_current_mrr_per_active_customer,
    
    -- Cohort quality indicator
    CASE 
        WHEN 100.0 * ccs.current_mrr / csm.starting_mrr >= 110 THEN 'Expanding'
        WHEN 100.0 * ccs.current_mrr / csm.starting_mrr >= 90 THEN 'Healthy'
        WHEN 100.0 * ccs.current_mrr / csm.starting_mrr >= 70 THEN 'Declining'
        ELSE 'At Risk'
    END as cohort_health,
    
    -- Strategic insights
    CASE 
        WHEN ca.cohort_age_months <= 3 THEN 'Onboarding phase - critical retention period'
        WHEN ca.cohort_age_months <= 6 THEN 'Early adoption - building habits'
        WHEN ca.cohort_age_months <= 12 THEN 'Maturing - expansion opportunities'
        ELSE 'Established - retention and advocacy focus'
    END as lifecycle_stage

FROM cohort_starting_metrics csm
JOIN cohort_current_status ccs ON csm.cohort_month = ccs.cohort_month
LEFT JOIN cohort_engagement ce ON csm.cohort_month = ce.cohort_month
JOIN cohort_age ca ON csm.cohort_month = ca.cohort_month
WHERE csm.cohort_size >= 5  -- Filter out very small cohorts
ORDER BY csm.cohort_month DESC
LIMIT 24;  -- Show last 24 months

/*
=============================================================================
SAMPLE OUTPUT INTERPRETATION:
=============================================================================

cohort_month: 2024-06-01
cohort_age_months: 6
cohort_size: 45
customer_retention_rate: 82.2%
revenue_retention_rate: 95.6%
cohort_health: "Healthy"
upgrade_rate: 11.1%

ANALYSIS:
6-month-old cohort showing solid retention. Revenue retention (95.6%) 
slightly below customer retention (82.2%) suggests some downgrades among
remaining customers, but upgrade rate of 11% is offsetting some churn.

Strong performance for this cohort age - typically see 75-80% retention
at 6 months. This cohort is outperforming benchmarks.

INSIGHTS:
- What was special about June 2024 signups?
- Which acquisition channel drove this cohort?
- Can we replicate their onboarding experience?

=============================================================================
KEY COMPARISONS TO MAKE:
=============================================================================

1. COHORT AGE PATTERNS:
   - Do newer cohorts retain better (improved onboarding)?
   - At what age do cohorts typically stabilize?
   - When is churn risk highest?

2. SEASONAL PATTERNS:
   - Do Q4 signups behave differently than Q1?
   - Are there holiday/budget cycle effects?

3. REVENUE VS CUSTOMER RETENTION:
   - Revenue retention > customer retention = expansion working
   - Revenue retention < customer retention = downgrade problem

4. UPGRADE BEHAVIOR:
   - Which cohorts upgrade fastest?
   - Are upgrades driven by age or by usage?

=============================================================================
STRATEGIC APPLICATIONS:
=============================================================================

PRODUCT IMPROVEMENTS:
Compare cohorts before/after feature releases to measure impact.

ACQUISITION OPTIMIZATION:
Identify which time periods produced best long-term customers.

FINANCIAL FORECASTING:
Use cohort retention curves to predict future revenue.

SEGMENT PRIORITIZATION:
Focus resources on cohorts with best retention characteristics.

=============================================================================
EXTENDED ANALYSIS QUERIES:
=============================================================================

-- 1. COHORT RETENTION CURVE (by month since signup)
WITH cohort_monthly_retention AS (
    SELECT 
        DATE_TRUNC('month', c.signup_date) as cohort_month,
        EXTRACT(MONTH FROM AGE(ca.activity_date, c.signup_date)) as months_since_signup,
        COUNT(DISTINCT c.customer_id) as active_customers
    FROM customers c
    JOIN customer_activity ca ON c.customer_id = ca.customer_id
    GROUP BY cohort_month, months_since_signup
)
SELECT * FROM cohort_monthly_retention
ORDER BY cohort_month, months_since_signup;

-- 2. COHORT COMPARISON BY ACQUISITION SOURCE
-- (Requires acquisition source field)
SELECT 
    acquisition_source,
    AVG(customer_retention_rate) as avg_retention,
    AVG(revenue_retention_rate) as avg_revenue_retention,
    COUNT(*) as cohort_count
FROM [this query]
GROUP BY acquisition_source;

-- 3. BEST VS WORST COHORTS
SELECT 
    cohort_month,
    revenue_retention_rate,
    customer_retention_rate,
    upgrade_rate,
    avg_usage_score
FROM [this query]
ORDER BY revenue_retention_rate DESC
LIMIT 5;  -- Top 5 best cohorts

=============================================================================
EXECUTIVE SUMMARY METRICS:
=============================================================================

Run this for board/exec reporting:

SELECT 
    -- Overall portfolio health
    AVG(customer_retention_rate) as avg_customer_retention,
    AVG(revenue_retention_rate) as avg_revenue_retention,
    SUM(current_mrr) as total_mrr,
    
    -- Cohort performance spread
    MAX(revenue_retention_rate) as best_cohort_retention,
    MIN(revenue_retention_rate) as worst_cohort_retention,
    
    -- Growth indicators
    AVG(upgrade_rate) as avg_upgrade_rate,
    SUM(starter_to_pro_upgrades + pro_to_enterprise_upgrades) as total_upgrades_last_period
    
FROM [this query]
WHERE cohort_age_months >= 6;  -- Mature cohorts only

=============================================================================
POTENTIAL EXTENSIONS:
=============================================================================

1. Add customer acquisition cost (CAC) by cohort
2. Calculate LTV:CAC ratios by cohort
3. Add time-to-value metrics (days until first value event)
4. Incorporate NPS trends over cohort lifetime
5. Add competitive loss analysis by cohort
6. Build predictive churn models using cohort patterns
7. Segment cohorts by industry, company size, or other firmographics

=============================================================================
*/
