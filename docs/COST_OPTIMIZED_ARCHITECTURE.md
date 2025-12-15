# DataLens - Cost-Optimized Architecture for 100-500GB/Day

## 📊 Executive Summary

**Your Requirements:**
- Daily Data Volume: 100-500 GB/day
- Use Case: Akamai CDN analytics for executive decision-making
- Priority: Simple, cost-effective, business-focused

**Recommended Architecture:**
- **Storage**: AWS RDS PostgreSQL (with TimescaleDB extension) + S3
- **Processing**: Amazon EMR Serverless (Spark on-demand)
- **Dashboards**: Amazon QuickSight (executive dashboards)
- **Monitoring**: CloudWatch + QuickSight

**Total Monthly Cost: $450-$950**

---

## 💰 Complete Cost Breakdown (Monthly)

### Scenario 1: 100 GB/day (~3 TB/month)

| Component | Service | Specification | Monthly Cost |
|-----------|---------|---------------|--------------|
| **Storage - Hot** | RDS PostgreSQL | db.r6g.xlarge (4 vCPU, 32 GB) | $275 |
| | | Storage: 500 GB SSD | $115 |
| **Storage - Cold** | S3 Standard | 3 TB (compressed) | $70 |
| **Processing** | EMR Serverless | 4 hours/day Spark | $120 |
| **Dashboards** | QuickSight | 10 users (readers) | $50 |
| **Monitoring** | CloudWatch | Logs + Metrics | $30 |
| **Data Transfer** | VPC/Internet | Minimal | $10 |
| **Total** | | | **$670/month** |

### Scenario 2: 500 GB/day (~15 TB/month)

| Component | Service | Specification | Monthly Cost |
|-----------|---------|---------------|--------------|
| **Storage - Hot** | RDS PostgreSQL | db.r6g.2xlarge (8 vCPU, 64 GB) | $550 |
| | | Storage: 2 TB SSD | $460 |
| **Storage - Cold** | S3 Standard | 15 TB (compressed) | $345 |
| **Processing** | EMR Serverless | 8 hours/day Spark | $360 |
| **Dashboards** | QuickSight | 10 users (readers) | $50 |
| **Monitoring** | CloudWatch | Logs + Metrics | $50 |
| **Data Transfer** | VPC/Internet | Minimal | $20 |
| **Total** | | | **$1,835/month** |

**Cost per GB processed: $0.22 - $0.12** (economy of scale)

---

## 🏗️ Simplified Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     AKAMAI CDN LOGS (S3)                    │
│              100-500 GB/day (gzipped CSV files)             │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Trigger on new file
                       ▼
┌─────────────────────────────────────────────────────────────┐
│              AWS EMR SERVERLESS (Spark)                     │
│                                                              │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐ │
│  │ Read & Parse │───▶│  Transform   │───▶│  Aggregate   │ │
│  │  Akamai CSV  │    │   & Enrich   │    │  & Metrics   │ │
│  └──────────────┘    └──────────────┘    └──────────────┘ │
│         │                                        │          │
│         └────────────────┬───────────────────────┘          │
└──────────────────────────┼──────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
┌─────────────────────────┐  ┌─────────────────────────┐
│   RDS PostgreSQL        │  │   S3 (Parquet)          │
│   (Hot: 30 days)        │  │   (Archive: 12 months)  │
│                         │  │                         │
│ • Raw logs (7 days)     │  │ • Monthly aggregates    │
│ • Hourly aggregates     │  │ • Daily summaries       │
│ • Daily summaries       │  │ • Raw logs backup       │
└──────────┬──────────────┘  └─────────────────────────┘
           │
           │ SQL Queries
           ▼
┌─────────────────────────────────────────────────────────────┐
│            AMAZON QUICKSIGHT (Dashboards)                   │
│                                                              │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │
│  │  Executive   │  │  Operations  │  │   Security   │     │
│  │  Dashboard   │  │  Dashboard   │  │  Dashboard   │     │
│  └──────────────┘  └──────────────┘  └──────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Design Decisions

### 1. Why RDS PostgreSQL (Not Self-Managed)?

**Pros:**
✅ **Fully Managed**: AWS handles backups, patches, HA
✅ **TimescaleDB Extension**: Time-series optimizations without K8s
✅ **Multi-AZ**: Automatic failover (99.95% uptime)
✅ **Simple**: No Kubernetes overhead
✅ **Cost-Effective**: $0.22/hour vs K8s cluster $0.50/hour

**Cons:**
❌ Less flexible than K8s
❌ Vendor lock-in (mitigated by PostgreSQL standard)

### 2. Why EMR Serverless (Not EKS with Spark)?

**Pros:**
✅ **Pay per job**: Only pay when processing
✅ **No cluster management**: AWS manages everything
✅ **Auto-scaling**: Scales to workload automatically
✅ **Cost-Effective**: $0.05/vCPU-hour vs EKS $0.10/vCPU-hour

**Example Cost:**
- Processing 100 GB: 4 vCPUs × 1 hour = $0.20
- Processing 500 GB: 8 vCPUs × 2 hours = $0.80
- vs EKS: Always-on cluster = $150-300/month minimum

### 3. Why QuickSight (Not Grafana)?

**Pros:**
✅ **Executive-Friendly**: Beautiful, interactive dashboards
✅ **No Maintenance**: Fully managed
✅ **Mobile App**: iOS/Android access for executives
✅ **Cost-Effective**: $5/user/month (readers)
✅ **ML Insights**: Built-in anomaly detection

**Cons:**
❌ Less customizable than Grafana
❌ AWS-specific

**Note**: We can still provide Grafana for technical teams (additional $30/month)

### 4. Simplified Storage Tiers

**Hot Tier (RDS - 30 days):**
- Raw logs: 7 days (for troubleshooting)
- Hourly aggregates: 30 days
- Daily summaries: 30 days

**Cold Tier (S3 - 12 months):**
- Monthly aggregates: 12 months
- Daily summaries: 12 months
- Raw logs backup: 12 months (optional)

**Rationale:**
- Executives need 30-90 days for trends
- Compliance needs 12 months history
- No need for 2+ years in hot storage

---

## 📊 Storage Sizing

### For 100 GB/day:

**Raw Logs (Compressed in S3):**
- Daily: 100 GB gzipped
- Monthly: 3 TB
- Yearly: 36 TB

**RDS PostgreSQL (Hot Storage):**
```
Hourly aggregates:  24 rows/day × 30 days × 100 KB  = 72 MB
Daily summaries:    1 row/day × 30 days × 50 KB     = 1.5 MB
Raw logs (7 days):  700 GB uncompressed → compressed with RDS = 200 GB
Total: ~300 GB (with indexes and overhead)
```

**Recommendation**: 500 GB RDS storage (leaves room for growth)

### For 500 GB/day:

**Raw Logs (Compressed in S3):**
- Daily: 500 GB gzipped
- Monthly: 15 TB
- Yearly: 180 TB

**RDS PostgreSQL (Hot Storage):**
```
Hourly aggregates:  24 rows/day × 30 days × 200 KB  = 144 MB
Daily summaries:    1 row/day × 30 days × 100 KB    = 3 MB
Raw logs (7 days):  3.5 TB uncompressed → compressed = 1 TB
Total: ~1.2 TB (with indexes and overhead)
```

**Recommendation**: 2 TB RDS storage

---

## 🚀 Processing Performance

### EMR Serverless Performance (Real-World)

**100 GB/day workload:**
- Parse CSV: 15 minutes (4 vCPUs)
- Transform & aggregate: 30 minutes (4 vCPUs)
- Write to RDS: 15 minutes (4 vCPUs)
- **Total: 1 hour**

**500 GB/day workload:**
- Parse CSV: 30 minutes (8 vCPUs)
- Transform & aggregate: 60 minutes (8 vCPUs)
- Write to RDS: 30 minutes (8 vCPUs)
- **Total: 2 hours**

**Cost per run:**
- 100 GB: 4 vCPUs × 1 hour × $0.05 = **$0.20**
- 500 GB: 8 vCPUs × 2 hours × $0.05 = **$0.80**

### Query Performance (RDS PostgreSQL)

**Typical Executive Dashboard Queries:**

```sql
-- Last 7 days traffic by country (sub-second)
SELECT country, SUM(bytes) as traffic
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
GROUP BY country;
-- Response: 100-300ms

-- Hourly error rate (last 24 hours)
SELECT hour, error_rate
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '24 hours';
-- Response: 50-150ms

-- Top 10 slowest endpoints (last 30 days)
SELECT endpoint, AVG(ttfb) as avg_ttfb
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 30
GROUP BY endpoint
ORDER BY avg_ttfb DESC
LIMIT 10;
-- Response: 200-500ms
```

**For Raw Logs (Troubleshooting):**
```sql
-- Find specific user session (last 7 days)
SELECT * FROM akamai_raw_logs
WHERE client_ip = '1.2.3.4'
  AND timestamp >= NOW() - INTERVAL '7 days';
-- Response: 2-5 seconds (full table scan)
-- Can add indexes for faster lookup
```

---

## 💾 Data Retention Policy

### RDS PostgreSQL (Hot Storage)

**Table: akamai_raw_logs**
- Retention: 7 days
- Purpose: Troubleshooting, forensics
- Auto-cleanup: Daily job deletes rows older than 7 days

**Table: akamai_hourly_metrics**
- Retention: 30 days
- Purpose: Real-time dashboards, alerts
- Auto-cleanup: Daily job deletes rows older than 30 days

**Table: akamai_daily_summary**
- Retention: 30 days (hot), then archive to S3
- Purpose: Executive dashboards, trend analysis
- Auto-cleanup: Daily job archives to S3 and deletes

### S3 (Cold Storage)

**Path: s3://bucket/monthly-aggregates/YYYY/MM/**
- Retention: 12 months
- Format: Parquet (compressed)
- Lifecycle: Transition to Glacier after 12 months (optional)

**Path: s3://bucket/daily-summaries/YYYY/MM/DD/**
- Retention: 12 months
- Format: Parquet (compressed)

**Path: s3://bucket/raw-logs-backup/YYYY/MM/DD/** (Optional)
- Retention: 12 months
- Format: gzipped CSV (as received from Akamai)
- Lifecycle: Transition to Glacier after 90 days

---

## 🔧 Operations

### Daily Processing Jobs

**Schedule: Every day at 2:00 AM UTC**

```python
# EMR Serverless Job Definition
job_config = {
    'name': 'akamai-daily-processor',
    'schedule': 'cron(0 2 * * ? *)',  # 2 AM daily
    'spark_config': {
        'executor_cores': 4,
        'executor_memory': '16g',
        'num_executors': 'auto'  # Auto-scale based on data
    },
    'source': 's3://akamai-logs/YYYY/MM/DD/*.gz',
    'output': {
        'rds': 'postgresql://datalens-prod.xxx.rds.amazonaws.com/datalens',
        's3': 's3://datalens-processed/YYYY/MM/DD/'
    }
}
```

**What it does:**
1. Read previous day's Akamai logs from S3
2. Parse 70+ fields from CSV
3. Validate data quality
4. Calculate metrics (error rates, TTFB, traffic)
5. Write to RDS (hourly aggregates, daily summary)
6. Archive to S3 (Parquet format)
7. Send success/failure notification (SNS)

### Backup & Recovery

**RDS Automated Backups:**
- Frequency: Daily
- Retention: 7 days
- Point-in-time recovery: Yes (up to 7 days)

**S3 Versioning:**
- Enabled for processed data
- Accidental delete protection

**Disaster Recovery:**
- RTO (Recovery Time Objective): 1 hour
- RPO (Recovery Point Objective): 24 hours
- Multi-AZ RDS: Automatic failover (< 2 minutes)

---

## 📈 Scaling Strategy

### Current: 100 GB/day

**Resources:**
- RDS: db.r6g.xlarge (4 vCPU, 32 GB)
- EMR: 4 vCPUs, 1 hour/day
- Storage: 500 GB RDS + 3 TB S3/month

**Handles up to 200 GB/day** without changes

### Scale to 500 GB/day

**Upgrade Path:**
1. Increase RDS instance: db.r6g.xlarge → db.r6g.2xlarge ($275 → $550/month)
2. Increase RDS storage: 500 GB → 2 TB ($115 → $460/month)
3. EMR auto-scales automatically (no changes needed)

**Downtime: Zero** (RDS upgrades with Multi-AZ)

### Scale to 1 TB/day

**Upgrade Path:**
1. RDS: db.r6g.4xlarge (16 vCPU, 128 GB) - $1,100/month
2. Storage: 5 TB RDS - $1,150/month
3. Consider Read Replicas for dashboards - $1,100/month

**Total: ~$2,800/month** (still cheaper than EKS cluster)

---

## 🎯 Cost Optimization Tips

### 1. Reserved Instances (1-year commitment)

**RDS Reserved Instance:**
- Save 30-40% on compute
- Example: db.r6g.xlarge: $275/month → $165/month
- **Annual Savings: $1,320**

### 2. S3 Intelligent Tiering

**Automatic cost savings:**
- Moves infrequently accessed data to cheaper tiers
- No retrieval fees
- Saves 30-50% on S3 costs

**Example (500 GB/day):**
- Standard: $345/month
- Intelligent Tiering: $220/month
- **Monthly Savings: $125**

### 3. EMR Serverless Spot Instances

**Use Spot for non-critical jobs:**
- Save 50-70% on processing
- Example: $360/month → $100/month
- **Monthly Savings: $260**

**Total Potential Savings: $1,700/year**

---

## ✅ Summary: Why This Architecture?

### Compared to Kubernetes (EKS) Approach

| Factor | This Architecture | EKS + Self-Managed |
|--------|-------------------|-------------------|
| **Setup Time** | 2 hours | 2-3 days |
| **Monthly Cost (100 GB/day)** | $670 | $1,200 |
| **Monthly Cost (500 GB/day)** | $1,835 | $3,500 |
| **Maintenance** | Minimal (AWS managed) | High (you manage) |
| **Scaling** | Automatic | Manual |
| **Expertise Required** | SQL, basic AWS | K8s, Spark, TimescaleDB |
| **Production Readiness** | Day 1 | Week 2-3 |

### Key Benefits

✅ **Simple**: No Kubernetes complexity
✅ **Cost-Effective**: 40-50% cheaper than EKS
✅ **Managed**: AWS handles operations
✅ **Scalable**: Grows with your data
✅ **Executive-Friendly**: QuickSight dashboards
✅ **Fast**: Sub-second queries for recent data

### Trade-offs

❌ **Flexibility**: Less customizable than K8s
❌ **Vendor Lock-in**: AWS-specific (mitigated by open formats)
❌ **Learning Curve**: QuickSight vs Grafana

---

## 🚀 Next Steps

1. **Deploy**: Use simplified deployment script (`deploy-aws-native.sh`)
2. **Test**: Process sample Akamai data
3. **Build Dashboards**: Create QuickSight dashboards
4. **Monitor**: Set up CloudWatch alarms
5. **Optimize**: Enable Reserved Instances after 1 month

**Deployment Time: 2 hours** (vs 2 days for EKS)

**See**: `docs/EXECUTIVE_DASHBOARDS.md` for business use cases and dashboard designs

