
This is a comprehensive SQL analytics portfolio demonstrating core Customer Success Operations capabilities through five production-ready analyses built with PostgreSQL. This project showcases the analytical foundation required to display insights that drive retention, expansion, and customer health management. Each analysis is designed to deliver actionable insights for Customer Success teams.

## Project Structure

```
├── data/
│   ├── 01_create_customers_table.sql      # Customer master data (1000 records)
│   └── 02_create_activity_table.sql       # Weekly activity metrics (25K+ records)
└── analysis/
    ├── 01_customer_health_scoring.sql     # Composite health scoring model
    ├── 02_churn_risk_identification.sql   # Multi-signal churn prediction
    ├── 03_expansion_opportunities.sql     # Upsell/upgrade identification
    ├── 04_usage_trend_analysis.sql        # Engagement trending over time
    └── 05_cohort_retention_analysis.sql   # Retention metrics by signup cohort
```

## Analyses Included

### 1. Customer Health Scoring
**Purpose:** Calculate a 0-100 health score for active customers to prioritize CS team outreach.

**Methodology:** Combines three weighted dimensions:
- Usage Health (40%): Product engagement and feature adoption
- Support Health (30%): Support ticket frequency and sentiment
- Engagement Health (30%): Login activity and NPS scores

**Output:** Health grades (A-F), recommended actions, and supporting metrics for each customer.

**Business Value:** Enables proactive interventions before customers churn, helps prioritize limited CS resources.

---

### 2. Churn Risk Identification
**Purpose:** Identify customers at risk of churning using multiple behavioral signals.

**Methodology:** Analyzes five risk indicators:
- Usage decline (comparing current vs. prior 4-week periods)
- Support burden (ticket volume as friction indicator)
- NPS deterioration (declining satisfaction scores)
- Login frequency decline (disengagement signal)
- Inactivity patterns (inconsistent usage)

**Output:** Risk scores (0-100), risk categories (Critical/High/Medium/Low), revenue at risk, and prioritized action list.

**Business Value:** Early warning system for revenue retention, quantifies at-risk MRR for forecasting.

---

### 3. Expansion Opportunities
**Purpose:** Find customers ready for upsells and upgrades based on product usage patterns.

**Methodology:** Identifies five expansion signals:
- Plan ceiling (high usage on lower-tier plans)
- Feature adoption depth (power user behavior)
- Growth trajectory (increasing usage trends)
- Customer satisfaction (high NPS scores)
- Product mastery (low support dependency)

**Output:** Expansion readiness scores, recommended opportunity types, estimated expansion revenue, and sales talking points.

**Business Value:** Drives revenue growth from existing customers, identifies natural expansion moments.

---

### 4. Usage Trend Analysis
**Purpose:** Track product engagement trends over time to spot patterns before they impact retention.

**Methodology:** Uses window functions to calculate:
- Week-over-week changes in key metrics
- 4-week rolling averages to smooth volatility
- Trend classification (Strong Growth/Improving/Stable/Declining)
- Engagement consistency scoring

**Output:** Trend scores, WoW percentage changes, moving averages, and prioritized intervention list.

**Business Value:** Catches declining engagement early, validates impact of product improvements, identifies customers needing habit reinforcement.

---

### 5. Cohort Retention Analysis
**Purpose:** Analyze retention and engagement patterns by signup cohort to understand customer lifecycle.

**Methodology:** Groups customers by signup month and tracks:
- Customer retention rates over time
- Revenue retention vs. customer retention
- Upgrade behavior by cohort
- Engagement patterns by customer age

**Output:** Retention metrics by cohort, revenue trends, cohort health indicators, and lifecycle stage insights.

**Business Value:** Validates product-market fit, measures impact of onboarding improvements, identifies which customer segments are most successful.

---

## Technical Skills Demonstrated

- **Complex SQL:** CTEs, window functions (LAG, LEAD, ROW_NUMBER), subqueries, JOINs
- **Analytical Techniques:** Cohort analysis, trend analysis, composite scoring, comparative metrics
- **Business Logic:** Weighted scoring models, risk stratification, threshold-based categorization
- **Data Aggregation:** Rolling averages, period-over-period comparisons, percentile calculations
- **Production Readiness:** Comprehensive documentation, clear comments, scalable query structure

## How to Use This Repository

### Setup Instructions

1. **Create the database schema:**
   ```sql
   -- Run in order:
   -- 1. Create and populate customers table
   \i data/01_create_customers_table.sql
   
   -- 2. Create and populate activity table
   \i data/02_create_activity_table.sql
   ```

2. **Run any analysis:**
   ```sql
   -- Each analysis file is standalone and can be run independently
   \i analysis/01_customer_health_scoring.sql
   ```

3. **Customize for your use case:**
   - Adjust health score weights in the scoring models
   - Modify risk thresholds based on your business context
   - Change date ranges in WHERE clauses as needed


## Data Model

**Customers Table:**
- customer_id (PK), company_name, signup_date, plan_type, industry, account_owner, status, mrr

**Customer Activity Table:**
- activity_id (PK), customer_id (FK), activity_date, logins_count, feature_usage_score, support_tickets_opened, nps_score

Mock data includes 1,000 customers with weekly activity records spanning 26 weeks, representing realistic SaaS usage patterns.


**Note:** This project uses mock data for demonstration purposes. 
