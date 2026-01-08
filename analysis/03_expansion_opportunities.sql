/*
=============================================================================
EXPANSION OPPORTUNITY IDENTIFICATION
=============================================================================

PURPOSE:
Identify customers ready for upsells, upgrades, or expansion based on
product usage patterns and engagement signals.

BUSINESS VALUE:
- Drives revenue growth from existing customer base
- Identifies natural expansion moments based on product behavior
- Prioritizes highest-probability upsell conversations
- Supports account planning and forecasting

METHODOLOGY:
Identifies expansion signals including:
1. Plan ceiling: High usage on lower-tier plans
2. Feature adoption: Strong engagement with core features
3. Growth trajectory: Increasing usage trends
4. User satisfaction: High NPS scores indicating readiness
5. Support maturity: Low ticket volume showing self-sufficiency

OUTPUTS:
- Expansion readiness score (0-100)
- Specific expansion opportunity type
- Estimated expansion revenue potential
- Recommended timing and talking points
=============================================================================
*/

-- Calculate recent usage patterns (last 30 days)
WITH recent_usage AS (
    SELECT 
        customer_id,
        AVG(logins_count) as avg_logins,
        AVG(feature_usage_score) as avg_usage_score,
        SUM(support_tickets_opened) as total_tickets,
        AVG(nps_score) as avg_nps,
        COUNT(*) as weeks_active
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY customer_id
),

-- Calculate usage trend (comparing last 30 days to previous 30 days)
usage_trend AS (
    SELECT 
        customer_id,
        AVG(CASE 
            WHEN activity_date >= CURRENT_DATE - INTERVAL '30 days' 
            THEN logins_count 
        END) as recent_logins,
        AVG(CASE 
            WHEN activity_date >= CURRENT_DATE - INTERVAL '60 days' 
                AND activity_date < CURRENT_DATE - INTERVAL '30 days'
            THEN logins_count 
        END) as prior_logins,
        AVG(CASE 
            WHEN activity_date >= CURRENT_DATE - INTERVAL '30 days' 
            THEN feature_usage_score 
        END) as recent_usage,
        AVG(CASE 
            WHEN activity_date >= CURRENT_DATE - INTERVAL '60 days' 
                AND activity_date < CURRENT_DATE - INTERVAL '30 days'
            THEN feature_usage_score 
        END) as prior_usage
    FROM customer_activity
    WHERE activity_date >= CURRENT_DATE - INTERVAL '60 days'
    GROUP BY customer_id
),

-- Identify expansion signals
expansion_signals AS (
    SELECT 
        ru.customer_id,
        
        -- Signal 1: Plan ceiling (using more than plan should allow)
        CASE 
            WHEN c.plan_type = 'Starter' AND ru.avg_usage_score >= 80 THEN 30
            WHEN c.plan_type = 'Starter' AND ru.avg_usage_score >= 60 THEN 20
            WHEN c.plan_type = 'Professional' AND ru.avg_usage_score >= 90 THEN 25
            WHEN c.plan_type = 'Professional' AND ru.avg_usage_score >= 75 THEN 15
            ELSE 0
        END as plan_ceiling_signal,
        
        -- Signal 2: Strong feature adoption
        CASE 
            WHEN ru.avg_usage_score >= 85 THEN 25
            WHEN ru.avg_usage_score >= 70 THEN 15
            ELSE 0
        END as adoption_signal,
        
        -- Signal 3: Growth trajectory
        CASE 
            WHEN ut.prior_usage IS NOT NULL 
                AND ut.recent_usage > ut.prior_usage * 1.3 THEN 20
            WHEN ut.prior_usage IS NOT NULL 
                AND ut.recent_usage > ut.prior_usage * 1.15 THEN 10
            ELSE 0
        END as growth_signal,
        
        -- Signal 4: High satisfaction
        CASE 
            WHEN ru.avg_nps >= 9 THEN 15
            WHEN ru.avg_nps >= 8 THEN 10
            WHEN ru.avg_nps >= 7 THEN 5
            ELSE 0
        END as satisfaction_signal,
        
        -- Signal 5: Product mastery (low support need)
        CASE 
            WHEN ru.total_tickets = 0 AND ru.avg_usage_score > 60 THEN 10
            WHEN ru.total_tickets <= 1 AND ru.avg_usage_score > 60 THEN 5
            ELSE 0
        END as mastery_signal,
        
        -- Store metrics for output
        ru.avg_logins,
        ru.avg_usage_score,
        ru.total_tickets,
        ru.avg_nps,
        ut.recent_usage,
        ut.prior_usage,
        c.plan_type,
        c.mrr
        
    FROM recent_usage ru
    JOIN customers c ON ru.customer_id = c.customer_id
    LEFT JOIN usage_trend ut ON ru.customer_id = ut.customer_id
    WHERE c.status = 'Active'
),

-- Calculate expansion readiness score
expansion_scores AS (
    SELECT 
        customer_id,
        
        -- Overall expansion readiness (sum of signals)
        plan_ceiling_signal + 
        adoption_signal + 
        growth_signal + 
        satisfaction_signal + 
        mastery_signal as expansion_score,
        
        -- Individual signals
        plan_ceiling_signal,
        adoption_signal,
        growth_signal,
        satisfaction_signal,
        mastery_signal,
        
        -- Supporting data
        avg_logins,
        avg_usage_score,
        total_tickets,
        avg_nps,
        recent_usage,
        prior_usage,
        plan_type,
        mrr
        
    FROM expansion_signals
)

-- Final output with expansion recommendations
SELECT 
    c.customer_id,
    c.company_name,
    c.plan_type as current_plan,
    c.mrr as current_mrr,
    c.account_owner,
    c.signup_date,
    EXTRACT(MONTH FROM AGE(CURRENT_DATE, c.signup_date)) as months_as_customer,
    
    -- Expansion assessment
    es.expansion_score,
    CASE 
        WHEN es.expansion_score >= 60 THEN 'Hot - Ready Now'
        WHEN es.expansion_score >= 40 THEN 'Warm - Qualified'
        WHEN es.expansion_score >= 20 THEN 'Developing - Monitor'
        ELSE 'Early - Nurture'
    END as expansion_readiness,
    
    -- Recommended expansion type
    CASE 
        WHEN c.plan_type = 'Starter' AND es.plan_ceiling_signal >= 20 
            THEN 'Upgrade to Professional'
        WHEN c.plan_type = 'Professional' AND es.plan_ceiling_signal >= 15 
            THEN 'Upgrade to Enterprise'
        WHEN es.adoption_signal >= 20 
            THEN 'Add-on features/modules'
        WHEN es.growth_signal >= 15 
            THEN 'Seat expansion'
        ELSE 'General expansion conversation'
    END as expansion_opportunity,
    
    -- Revenue potential
    CASE 
        WHEN c.plan_type = 'Starter' THEN 150.0  -- Typical upgrade delta
        WHEN c.plan_type = 'Professional' THEN 700.0  -- Typical upgrade delta
        ELSE c.mrr * 0.30  -- Conservative 30% expansion
    END as estimated_expansion_mrr,
    
    -- Signal breakdown
    CASE WHEN es.plan_ceiling_signal > 0 THEN '✓ At plan limits' ELSE NULL END as ceiling_flag,
    CASE WHEN es.adoption_signal > 0 THEN '✓ Power user' ELSE NULL END as adoption_flag,
    CASE WHEN es.growth_signal > 0 THEN '✓ Growing fast' ELSE NULL END as growth_flag,
    CASE WHEN es.satisfaction_signal > 0 THEN '✓ High NPS' ELSE NULL END as satisfaction_flag,
    CASE WHEN es.mastery_signal > 0 THEN '✓ Product mastery' ELSE NULL END as mastery_flag,
    
    -- Supporting metrics
    ROUND(es.avg_usage_score, 1) as avg_usage_score,
    ROUND(es.avg_logins, 1) as avg_weekly_logins,
    es.total_tickets as tickets_last_30d,
    ROUND(es.avg_nps, 1) as nps_score,
    
    -- Usage growth indicator
    CASE 
        WHEN es.prior_usage IS NOT NULL THEN 
            ROUND(((es.recent_usage - es.prior_usage) / es.prior_usage * 100), 1)
        ELSE NULL
    END as usage_growth_pct,
    
    -- Talking points for sales conversation
    CASE 
        WHEN es.expansion_score >= 60 THEN 
            'Customer is maxing out current plan. Strong adoption and satisfaction make this a low-risk upsell conversation.'
        WHEN es.expansion_score >= 40 THEN 
            'Usage patterns indicate readiness for expansion. Schedule value review to discuss growth needs.'
        ELSE 
            'Continue building value. Monitor for increased usage patterns.'
    END as sales_talking_points

FROM expansion_scores es
JOIN customers c ON es.customer_id = c.customer_id
WHERE es.expansion_score >= 20  -- Only show meaningful opportunities
  AND c.plan_type != 'Enterprise'  -- Can't upgrade from top tier
ORDER BY es.expansion_score DESC, c.mrr DESC
LIMIT 100;

/*
=============================================================================
SAMPLE OUTPUT INTERPRETATION:
=============================================================================

customer_id: 234
company_name: "GrowthCo"
current_plan: "Starter"
expansion_score: 75
expansion_readiness: "Hot - Ready Now"
expansion_opportunity: "Upgrade to Professional"
estimated_expansion_mrr: $150

SIGNALS:
✓ At plan limits (usage at 88%)
✓ Power user (strong feature adoption)
✓ Growing fast (35% usage increase)
✓ High NPS (score of 9)

SALES TALKING POINTS:
"Customer is maxing out current plan. Strong adoption and satisfaction 
make this a low-risk upsell conversation."

RECOMMENDED APPROACH:
1. CSM schedules "growth planning" call
2. Show how Professional plan unlocks their needs
3. Highlight features they're already trying to use
4. Offer smooth transition with no disruption
5. Close with multi-year discount if appropriate

=============================================================================
PORTFOLIO-LEVEL ANALYSIS:
=============================================================================

Run this to see total expansion pipeline:

SELECT 
    expansion_readiness,
    COUNT(*) as opportunity_count,
    SUM(estimated_expansion_mrr) as total_pipeline_mrr,
    AVG(expansion_score) as avg_readiness_score
FROM [this query]
GROUP BY expansion_readiness
ORDER BY avg_readiness_score DESC;

Expected output might show:
- Hot - Ready Now: 15 customers, $2,250 MRR pipeline
- Warm - Qualified: 42 customers, $4,800 MRR pipeline

=============================================================================
SALES TEAM INTEGRATION:
=============================================================================

This query output can be used to:
1. Generate weekly expansion opportunity reports
2. Trigger automated outreach sequences
3. Set CSM KPIs around expansion identified vs closed
4. Feed CRM with enrichment data
5. Build predictive expansion models

=============================================================================
POTENTIAL EXTENSIONS:
=============================================================================

1. Add industry/vertical benchmarking
2. Include competitive win-back opportunities
3. Add contract renewal proximity
4. Weight by customer LTV/strategic importance
5. Incorporate marketing engagement signals
6. Add team/seat count for multi-user upsells

=============================================================================
*/
