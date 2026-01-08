/*
CHURN RISK IDENTIFICATION

PURPOSE:
Identify customers at high risk of churning based on multiple behavioral
signals and product usage patterns.

VALUE:
- Early warning system to prevent revenue loss
- Prioritizes outreach to saveable accounts
- Quantifies potential revenue at risk
- Informs retention strategy and resource allocation

CHURN RISK INDICATORS:
1. Usage decline: Week-over-week drop in engagement
2. Support burden: High ticket volume indicating friction
3. NPS deterioration: Declining satisfaction scores
4. Login frequency: Reduced product engagement
5. Feature abandonment: Decreasing feature adoption

OUTPUTS:
- Risk score (0-100, higher = more risk)
- Individual risk factors flagged
- Estimated revenue at risk
- Prioritized action list for CS team

*/

-- Calculate current period metrics (last 4 weeks)
WITH current_metrics AS (
    SELECT 
        customer_id,
        AVG(logins_count) as current_avg_logins,
        AVG(feature_usage_score) as current_avg_usage,
        SUM(support_tickets_opened) as current_tickets,
        AVG(nps_score) as current_avg_nps,
        COUNT(*) as current_weeks_active
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '4 weeks'
      AND activity_date < CURRENT_DATE
    GROUP BY customer_id
),

-- Calculate prior period metrics (weeks 5-8 ago for comparison)
prior_metrics AS (
    SELECT 
        customer_id,
        AVG(logins_count) as prior_avg_logins,
        AVG(feature_usage_score) as prior_avg_usage,
        SUM(support_tickets_opened) as prior_tickets,
        AVG(nps_score) as prior_avg_nps
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '8 weeks'
      AND activity_date < CURRENT_DATE - INTERVAL '4 weeks'
    GROUP BY customer_id
),

-- Identify churn risk signals
risk_signals AS (
    SELECT 
        cm.customer_id,
        
        -- Signal 1: Usage decline
        CASE 
            WHEN pm.prior_avg_usage IS NOT NULL 
                AND cm.current_avg_usage < pm.prior_avg_usage * 0.5 THEN 25
            WHEN pm.prior_avg_usage IS NOT NULL 
                AND cm.current_avg_usage < pm.prior_avg_usage * 0.7 THEN 15
            WHEN cm.current_avg_usage < 40 THEN 10
            ELSE 0
        END as usage_decline_risk,
        
        -- Signal 2: High support burden
        CASE 
            WHEN cm.current_tickets >= 4 THEN 25
            WHEN cm.current_tickets = 3 THEN 15
            WHEN cm.current_tickets = 2 THEN 5
            ELSE 0
        END as support_burden_risk,
        
        -- Signal 3: NPS deterioration
        CASE 
            WHEN cm.current_avg_nps IS NOT NULL AND cm.current_avg_nps < 5 THEN 20
            WHEN cm.current_avg_nps IS NOT NULL AND cm.current_avg_nps < 7 THEN 10
            WHEN pm.prior_avg_nps IS NOT NULL 
                AND cm.current_avg_nps < pm.prior_avg_nps - 2 THEN 15
            ELSE 0
        END as nps_decline_risk,
        
        -- Signal 4: Low login frequency
        CASE 
            WHEN cm.current_avg_logins < 10 THEN 20
            WHEN cm.current_avg_logins < 20 THEN 10
            WHEN pm.prior_avg_logins IS NOT NULL 
                AND cm.current_avg_logins < pm.prior_avg_logins * 0.6 THEN 10
            ELSE 0
        END as login_decline_risk,
        
        -- Signal 5: Inactivity
        CASE 
            WHEN cm.current_weeks_active < 2 THEN 15
            ELSE 0
        END as inactivity_risk,
        
        -- Store metrics for output
        cm.current_avg_usage,
        pm.prior_avg_usage,
        cm.current_avg_logins,
        pm.prior_avg_logins,
        cm.current_tickets,
        cm.current_avg_nps
        
    FROM current_metrics cm
    LEFT JOIN prior_metrics pm ON cm.customer_id = pm.customer_id
),

-- Calculate overall risk score
risk_scores AS (
    SELECT 
        customer_id,
        
        -- Sum all risk signals (max 100)
        LEAST(
            usage_decline_risk + 
            support_burden_risk + 
            nps_decline_risk + 
            login_decline_risk + 
            inactivity_risk,
            100
        ) as churn_risk_score,
        
        -- Individual signals
        usage_decline_risk,
        support_burden_risk,
        nps_decline_risk,
        login_decline_risk,
        inactivity_risk,
        
        -- Supporting metrics
        current_avg_usage,
        prior_avg_usage,
        current_avg_logins,
        prior_avg_logins,
        current_tickets,
        current_avg_nps
        
    FROM risk_signals
)

-- Final output with customer details and prioritization
SELECT 
    c.customer_id,
    c.company_name,
    c.plan_type,
    c.mrr,
    c.account_owner,
    c.signup_date,
    
    -- Risk assessment
    rs.churn_risk_score,
    CASE 
        WHEN rs.churn_risk_score >= 60 THEN 'Critical Risk'
        WHEN rs.churn_risk_score >= 40 THEN 'High Risk'
        WHEN rs.churn_risk_score >= 20 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END as risk_category,
    
    -- Risk factors (show which signals are firing)
    CASE WHEN rs.usage_decline_risk > 0 THEN '⚠ Usage Declining' ELSE NULL END as usage_flag,
    CASE WHEN rs.support_burden_risk > 0 THEN '⚠ High Support Load' ELSE NULL END as support_flag,
    CASE WHEN rs.nps_decline_risk > 0 THEN '⚠ NPS Concerns' ELSE NULL END as nps_flag,
    CASE WHEN rs.login_decline_risk > 0 THEN '⚠ Login Decline' ELSE NULL END as login_flag,
    CASE WHEN rs.inactivity_risk > 0 THEN '⚠ Low Activity' ELSE NULL END as activity_flag,
    
    -- Revenue at risk
    c.mrr as monthly_revenue_at_risk,
    c.mrr * 12 as annual_revenue_at_risk,
    
    -- Supporting data
    ROUND(rs.current_avg_usage, 1) as current_usage,
    ROUND(rs.prior_avg_usage, 1) as prior_usage,
    ROUND(rs.current_avg_logins, 1) as current_logins,
    ROUND(rs.prior_avg_logins, 1) as prior_logins,
    rs.current_tickets as tickets_last_4wks,
    ROUND(rs.current_avg_nps, 1) as current_nps,
    
    -- Recommended action
    CASE 
        WHEN rs.churn_risk_score >= 60 THEN 'URGENT: Executive escalation + immediate intervention'
        WHEN rs.churn_risk_score >= 40 THEN 'HIGH: Schedule check-in call this week'
        WHEN rs.churn_risk_score >= 20 THEN 'MEDIUM: Proactive email outreach'
        ELSE 'LOW: Monitor next cycle'
    END as recommended_action

FROM risk_scores rs
JOIN customers c ON rs.customer_id = c.customer_id
WHERE c.status IN ('Active', 'At Risk')  -- Only analyze non-churned customers
  AND rs.churn_risk_score > 0  -- Only show customers with some risk
ORDER BY rs.churn_risk_score DESC, c.mrr DESC
LIMIT 100;

/*
SAMPLE OUTPUT INTERPRETATION:

customer_id: 456
company_name: "TechStart Inc"
churn_risk_score: 75
risk_category: "Critical Risk"
monthly_revenue_at_risk: $199
annual_revenue_at_risk: $2,388

RISK FLAGS:
 Usage Declining (usage dropped from 85 to 35)
 High Support Load (4 tickets in last 4 weeks)
 NPS Concerns (score dropped to 4)

RECOMMENDED ACTION: URGENT: Executive escalation + immediate intervention

PLAYBOOK:
1. CSM reaches out within 24 hours
2. Root cause analysis on usage decline
3. Address support issues blocking adoption
4. Executive sponsor engagement if needed
5. Create success plan with clear milestones

AGGREGATE INSIGHTS:

Run this to see portfolio-level risk:

SELECT 
    risk_category,
    COUNT(*) as customer_count,
    SUM(monthly_revenue_at_risk) as total_mrr_at_risk,
    AVG(churn_risk_score) as avg_risk_score
FROM [this query]
GROUP BY risk_category
ORDER BY avg_risk_score DESC;

POTENTIAL EXTENSIONS:

1. Add time-to-renewal proximity weighting
2. Incorporate support ticket sentiment analysis
3. Add product usage pattern clustering
4. Include competitive intelligence signals
5. Build predictive model using historical churn data

*/
