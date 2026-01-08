/*
=============================================================================
USAGE TREND ANALYSIS
=============================================================================

PURPOSE:
Track product usage trends over time to identify patterns, seasonality,
and early indicators of customer health changes.

BUSINESS VALUE:
- Identifies engagement trends before they become problems
- Enables proactive interventions during usage dips
- Validates product improvements and feature launches
- Supports executive reporting on product adoption
- Informs customer segmentation strategies

METHODOLOGY:
Analyzes usage patterns across multiple dimensions:
1. Week-over-week changes in key metrics
2. Rolling 4-week averages to smooth volatility
3. Trend direction (improving, stable, declining)
4. Velocity of change
5. Consistency of engagement

OUTPUTS:
- Trend scores and classifications
- Week-over-week percentage changes
- Moving averages for key metrics
- Ranked list of improving/declining accounts
=============================================================================
*/

-- Calculate weekly metrics with window functions
WITH weekly_metrics AS (
    SELECT 
        customer_id,
        activity_date,
        logins_count,
        feature_usage_score,
        support_tickets_opened,
        nps_score,
        
        -- Previous week metrics using LAG
        LAG(logins_count, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY activity_date
        ) as prev_week_logins,
        
        LAG(feature_usage_score, 1) OVER (
            PARTITION BY customer_id 
            ORDER BY activity_date
        ) as prev_week_usage,
        
        -- 4-week rolling averages
        AVG(logins_count) OVER (
            PARTITION BY customer_id 
            ORDER BY activity_date
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) as rolling_4wk_logins,
        
        AVG(feature_usage_score) OVER (
            PARTITION BY customer_id 
            ORDER BY activity_date
            ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
        ) as rolling_4wk_usage,
        
        -- Ranking within customer's own history
        ROW_NUMBER() OVER (
            PARTITION BY customer_id 
            ORDER BY activity_date DESC
        ) as weeks_ago
        
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '12 weeks'
),

-- Calculate most recent metrics and trends
recent_trends AS (
    SELECT 
        customer_id,
        
        -- Most recent week (weeks_ago = 1)
        MAX(CASE WHEN weeks_ago = 1 THEN logins_count END) as current_logins,
        MAX(CASE WHEN weeks_ago = 1 THEN feature_usage_score END) as current_usage,
        MAX(CASE WHEN weeks_ago = 1 THEN rolling_4wk_logins END) as current_4wk_avg_logins,
        MAX(CASE WHEN weeks_ago = 1 THEN rolling_4wk_usage END) as current_4wk_avg_usage,
        
        -- Previous week (weeks_ago = 2)
        MAX(CASE WHEN weeks_ago = 2 THEN logins_count END) as prev_logins,
        MAX(CASE WHEN weeks_ago = 2 THEN feature_usage_score END) as prev_usage,
        
        -- 4 weeks ago baseline for longer-term trend
        MAX(CASE WHEN weeks_ago = 5 THEN rolling_4wk_logins END) as baseline_4wk_logins,
        MAX(CASE WHEN weeks_ago = 5 THEN rolling_4wk_usage END) as baseline_4wk_usage,
        
        -- Count active weeks in last 8 weeks
        COUNT(CASE WHEN weeks_ago <= 8 THEN 1 END) as active_weeks_count
        
    FROM weekly_metrics
    GROUP BY customer_id
),

-- Calculate trend indicators and scores
trend_analysis AS (
    SELECT 
        customer_id,
        
        -- Week-over-week changes
        current_logins,
        prev_logins,
        CASE 
            WHEN prev_logins > 0 THEN 
                ROUND(((current_logins - prev_logins)::NUMERIC / prev_logins * 100), 1)
            ELSE NULL
        END as wow_login_change_pct,
        
        current_usage,
        prev_usage,
        CASE 
            WHEN prev_usage > 0 THEN 
                ROUND(((current_usage - prev_usage)::NUMERIC / prev_usage * 100), 1)
            ELSE NULL
        END as wow_usage_change_pct,
        
        -- 4-week trend (comparing rolling averages)
        current_4wk_avg_logins,
        baseline_4wk_logins,
        CASE 
            WHEN baseline_4wk_logins > 0 THEN 
                ROUND(((current_4wk_avg_logins - baseline_4wk_logins)::NUMERIC / baseline_4wk_logins * 100), 1)
            ELSE NULL
        END as four_week_login_trend_pct,
        
        current_4wk_avg_usage,
        baseline_4wk_usage,
        CASE 
            WHEN baseline_4wk_usage > 0 THEN 
                ROUND(((current_4wk_avg_usage - baseline_4wk_usage)::NUMERIC / baseline_4wk_usage * 100), 1)
            ELSE NULL
        END as four_week_usage_trend_pct,
        
        -- Activity consistency
        active_weeks_count
        
    FROM recent_trends
),

-- Score trends and classify
trend_scores AS (
    SELECT 
        ta.*,
        
        -- Trend score components
        CASE 
            WHEN four_week_usage_trend_pct > 20 THEN 30
            WHEN four_week_usage_trend_pct > 10 THEN 20
            WHEN four_week_usage_trend_pct > 0 THEN 10
            WHEN four_week_usage_trend_pct > -10 THEN 0
            WHEN four_week_usage_trend_pct > -20 THEN -10
            ELSE -20
        END as usage_trend_score,
        
        CASE 
            WHEN four_week_login_trend_pct > 20 THEN 20
            WHEN four_week_login_trend_pct > 10 THEN 10
            WHEN four_week_login_trend_pct > 0 THEN 5
            WHEN four_week_login_trend_pct > -10 THEN 0
            WHEN four_week_login_trend_pct > -20 THEN -10
            ELSE -15
        END as login_trend_score,
        
        CASE 
            WHEN active_weeks_count >= 7 THEN 10
            WHEN active_weeks_count >= 5 THEN 5
            WHEN active_weeks_count >= 3 THEN 0
            ELSE -10
        END as consistency_score
        
    FROM trend_analysis ta
)

-- Final output with customer details and trend classifications
SELECT 
    c.customer_id,
    c.company_name,
    c.plan_type,
    c.mrr,
    c.account_owner,
    c.status,
    
    -- Overall trend score
    ts.usage_trend_score + ts.login_trend_score + ts.consistency_score as overall_trend_score,
    
    -- Trend classification
    CASE 
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= 30 THEN 'Strong Growth'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= 10 THEN 'Improving'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= -10 THEN 'Stable'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= -30 THEN 'Declining'
        ELSE 'Sharp Decline'
    END as trend_category,
    
    -- Current state
    ROUND(ts.current_usage, 1) as current_week_usage,
    ROUND(ts.current_logins, 1) as current_week_logins,
    
    -- Short-term trends (WoW)
    ts.wow_usage_change_pct as wow_usage_change,
    ts.wow_login_change_pct as wow_login_change,
    
    -- Longer-term trends (4-week rolling)
    ROUND(ts.current_4wk_avg_usage, 1) as four_week_avg_usage,
    ts.four_week_usage_trend_pct as usage_trend_4wk,
    ROUND(ts.current_4wk_avg_logins, 1) as four_week_avg_logins,
    ts.four_week_login_trend_pct as login_trend_4wk,
    
    -- Engagement consistency
    ts.active_weeks_count as active_weeks_last_8,
    CASE 
        WHEN ts.active_weeks_count >= 7 THEN 'Highly Consistent'
        WHEN ts.active_weeks_count >= 5 THEN 'Mostly Consistent'
        WHEN ts.active_weeks_count >= 3 THEN 'Sporadic'
        ELSE 'Rare/Inactive'
    END as engagement_consistency,
    
    -- Recommended action based on trend
    CASE 
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= 30 THEN 
            'Capitalize on momentum - explore expansion opportunities'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= 10 THEN 
            'Positive trajectory - reinforce good habits'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= -10 THEN 
            'Monitor - ensure stability continues'
        WHEN ts.usage_trend_score + ts.login_trend_score + ts.consistency_score >= -30 THEN 
            'Intervention needed - schedule check-in'
        ELSE 
            'URGENT - immediate outreach required'
    END as recommended_action

FROM trend_scores ts
JOIN customers c ON ts.customer_id = c.customer_id
WHERE c.status IN ('Active', 'At Risk')
ORDER BY 
    -- Sort by trend score, then by MRR to prioritize high-value declining accounts
    (ts.usage_trend_score + ts.login_trend_score + ts.consistency_score) ASC,
    c.mrr DESC
LIMIT 100;

/*
=============================================================================
SAMPLE OUTPUT INTERPRETATION:
=============================================================================

customer_id: 789
company_name: "SlowStart Co"
overall_trend_score: -35
trend_category: "Sharp Decline"
current_week_usage: 28
wow_usage_change: -45.2%
usage_trend_4wk: -38.5%
engagement_consistency: "Sporadic"

ANALYSIS:
Customer showing concerning downward trajectory across multiple metrics.
Both short-term (WoW) and longer-term (4-week) trends are negative.
Sporadic engagement indicates they're struggling to build habits.

RECOMMENDED ACTION: URGENT - immediate outreach required

PLAYBOOK:
1. Same-day outreach from CSM
2. Understand what changed 4 weeks ago
3. Identify adoption barriers
4. Create structured onboarding plan
5. Set up weekly check-ins for next month

=============================================================================
PORTFOLIO HEALTH DASHBOARD:
=============================================================================

Run this to see overall portfolio trends:

SELECT 
    trend_category,
    COUNT(*) as customer_count,
    ROUND(AVG(overall_trend_score), 1) as avg_trend_score,
    SUM(mrr) as total_mrr,
    ROUND(AVG(usage_trend_4wk), 1) as avg_usage_trend_pct
FROM [this query]
GROUP BY trend_category
ORDER BY avg_trend_score DESC;

Expected insights:
- What % of portfolio is declining vs growing?
- Where is MRR concentrated (healthy or at-risk)?
- Are trends accelerating or stabilizing?

=============================================================================
TIME-BASED SEGMENTATION:
=============================================================================

Use this analysis to segment customers:

ACCELERATING: Strong growth + high consistency
→ Upsell targets, case study candidates

STABLE POWER USERS: High usage + stable trends
→ Retain, ask for referrals

VOLATILE: Inconsistent engagement
→ Build better habits, structured check-ins

DECLINING: Negative trends
→ Intervention, understand barriers

ABANDONING: Sharp decline + low consistency
→ Save or harvest campaign

=============================================================================
POTENTIAL EXTENSIONS:
=============================================================================

1. Add seasonal adjustment for holiday patterns
2. Compare against cohort/industry benchmarks
3. Add statistical significance testing
4. Build predictive scoring (next 30-day forecast)
5. Incorporate external factors (feature releases, onboarding changes)
6. Add team/company size as a normalizing factor

=============================================================================
*/
