/*
CUSTOMER HEALTH SCORING MODEL

PURPOSE:
Calculate a comprehensive health score (0-100) for each active customer
to prioritize outreach and identify accounts needing attention.

BUSINESS VALUE:
- Enables proactive intervention
- Helps team prioritize pain points
- Provides early warning system before customers churn
- Supports executive reporting on portfolio health

HEALTH SCORE FORMULA:
Combines three weighted dimensions:
- Usage Health (40%): Product engagement and feature adoption
- Support Health (30%): Support ticket frequency and recency
- Engagement Health (30%): Login activity and NPS sentiment

OUTPUTS:
- Overall health score (0-100)
- Individual dimension scores
- Health grade (A/B/C/D/F)
- Recommended action 
*/

-- Main health scoring calculation
WITH recent_activity AS (
    -- Get last 30 days of activity metrics per customer
    SELECT 
        customer_id,
        AVG(feature_usage_score) as avg_usage_score,
        AVG(logins_count) as avg_logins,
        SUM(support_tickets_opened) as total_tickets,
        AVG(nps_score) as avg_nps,
        COUNT(*) as weeks_with_activity
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY customer_id
),

-- Calculate individual health dimensions
health_dimensions AS (
    SELECT 
        ra.customer_id,
        
        -- Usage Health (0-100): Based on feature usage score
        COALESCE(ra.avg_usage_score, 0) as usage_health,
        
        -- Support Health (0-100): Inverse of support burden
        -- 0 tickets = 100, scales down as tickets increase
        CASE 
            WHEN ra.total_tickets = 0 THEN 100
            WHEN ra.total_tickets = 1 THEN 85
            WHEN ra.total_tickets = 2 THEN 70
            WHEN ra.total_tickets = 3 THEN 50
            WHEN ra.total_tickets >= 4 THEN 30
            ELSE 100
        END as support_health,
        
        -- Engagement Health (0-100): Login frequency + NPS
        CASE 
            WHEN ra.avg_logins >= 40 THEN 90
            WHEN ra.avg_logins >= 30 THEN 75
            WHEN ra.avg_logins >= 20 THEN 60
            WHEN ra.avg_logins >= 10 THEN 40
            ELSE 20
        END + 
        CASE 
            WHEN ra.avg_nps >= 9 THEN 10
            WHEN ra.avg_nps >= 7 THEN 5
            WHEN ra.avg_nps >= 5 THEN 0
            WHEN ra.avg_nps < 5 THEN -10
            ELSE 0
        END as engagement_health,
        
        -- Store raw metrics for reference
        ra.avg_usage_score,
        ra.avg_logins,
        ra.total_tickets,
        ra.avg_nps
        
    FROM recent_activity ra
),

-- Calculate weighted overall health score
overall_health AS (
    SELECT 
        hd.customer_id,
        
        -- Individual dimension scores
        ROUND(hd.usage_health, 1) as usage_health_score,
        ROUND(hd.support_health, 1) as support_health_score,
        ROUND(hd.engagement_health, 1) as engagement_health_score,
        
        -- Weighted overall score: Usage 40%, Support 30%, Engagement 30%
        ROUND(
            (hd.usage_health * 0.40) + 
            (hd.support_health * 0.30) + 
            (hd.engagement_health * 0.30),
            1
        ) as overall_health_score,
        
        -- Raw metrics
        hd.avg_usage_score,
        hd.avg_logins,
        hd.total_tickets,
        hd.avg_nps
        
    FROM health_dimensions hd
)

-- Final output with customer details and health grades
SELECT 
    c.customer_id,
    c.company_name,
    c.plan_type,
    c.mrr,
    c.account_owner,
    
    -- Health scores
    oh.overall_health_score,
    oh.usage_health_score,
    oh.support_health_score,
    oh.engagement_health_score,
    
    -- Health grade
    CASE 
        WHEN oh.overall_health_score >= 80 THEN 'A - Healthy'
        WHEN oh.overall_health_score >= 60 THEN 'B - Good'
        WHEN oh.overall_health_score >= 40 THEN 'C - At Risk'
        WHEN oh.overall_health_score >= 20 THEN 'D - High Risk'
        ELSE 'F - Critical'
    END as health_grade,
    
    -- Recommended action
    CASE 
        WHEN oh.overall_health_score >= 80 THEN 'Upsell opportunity - customer thriving'
        WHEN oh.overall_health_score >= 60 THEN 'Check-in - ensure continued success'
        WHEN oh.overall_health_score >= 40 THEN 'Intervention needed - declining engagement'
        ELSE 'Urgent outreach - churn risk high'
    END as recommended_action,
    
    -- Supporting metrics
    ROUND(oh.avg_usage_score, 1) as avg_feature_usage,
    ROUND(oh.avg_logins, 1) as avg_weekly_logins,
    oh.total_tickets as tickets_last_30d,
    ROUND(oh.avg_nps, 1) as avg_nps_score

FROM overall_health oh
JOIN customers c ON oh.customer_id = c.customer_id
WHERE c.status = 'Active'  -- Only score active customers
ORDER BY oh.overall_health_score ASC, c.mrr DESC
LIMIT 100;

/*
SAMPLE OUTPUT INTERPRETATION:

customer_id: 127
company_name: "Acme Corp"
overall_health_score: 45.2
health_grade: "C - At Risk"
recommended_action: "Intervention needed - declining engagement"

BREAKDOWN:
- usage_health_score: 35 (Low feature adoption)
- support_health_score: 70 (Moderate ticket volume)
- engagement_health_score: 35 (Declining logins, poor NPS)

ACTION: Team should schedule check-in call to understand barriers
to adoption and address satisfaction concerns.

*/
