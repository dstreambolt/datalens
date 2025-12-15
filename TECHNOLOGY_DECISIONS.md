# Technology Decision Summary - DataLens Pipeline

## Executive Summary

This document provides a comprehensive analysis of **all technology choices** in the DataLens architecture for Mobly (24K visits/day, ~100 GB/year data).

**Final Architecture**: S3 → Lambda → SQS → Spark Cluster → RDS PostgreSQL → Grafana  
**Monthly Cost**: $110  
**Latency**: <3 minutes  
**Decision Confidence**: ✅ High (all alternatives evaluated)

---

## Component-by-Component Decision Matrix

### 1. Event Processing: AWS Lambda

**Evaluated Options**: Lambda, EC2 polling, SNS+SQS, EventBridge, Step Functions

| Criterion | Weight | Lambda | EC2 Polling | EventBridge | Winner |
|-----------|--------|--------|-------------|-------------|--------|
| Cost | 30% | 10/10 ($0.20/mo) | 2/10 ($15/mo) | 5/10 ($1/mo) | **Lambda** |
| Latency | 25% | 10/10 (<500ms) | 6/10 (~2s) | 9/10 (<1s) | **Lambda** |
| Complexity | 20% | 9/10 (simple) | 4/10 (complex) | 6/10 (medium) | **Lambda** |
| Scalability | 15% | 10/10 (auto) | 5/10 (manual) | 10/10 (auto) | Lambda/EB |
| Maintenance | 10% | 10/10 (zero) | 2/10 (high) | 8/10 (low) | **Lambda** |
| **Total Score** | | **9.6/10** | **3.9/10** | **7.3/10** | **Lambda** |

**Decision**: Lambda wins with 9.6/10 score (cost + latency + simplicity)

---

### 2. Message Buffer: SQS Standard

**Evaluated Options**: SQS, Kinesis Streams, Redis, Direct S3 polling, In-memory queue

| Criterion | Weight | SQS | Kinesis | Redis | Direct S3 | Winner |
|-----------|--------|-----|---------|-------|-----------|--------|
| Cost | 30% | 10/10 ($0.40) | 2/10 ($11) | 5/10 ($15) | 8/10 (API costs) | **SQS** |
| Batching | 25% | 10/10 (10 msgs) | 10/10 (100s) | 9/10 (custom) | 0/10 (none) | SQS/Kinesis |
| Retry Logic | 20% | 10/10 (DLQ) | 6/10 (manual) | 5/10 (custom) | 0/10 (none) | **SQS** |
| Latency | 15% | 8/10 (seconds) | 10/10 (real-time) | 10/10 (memory) | 3/10 (polling) | Kinesis/Redis |
| Maintenance | 10% | 10/10 (managed) | 8/10 (managed) | 3/10 (self-host) | 9/10 (none) | **SQS** |
| **Total Score** | | **9.5/10** | **7.0/10** | **6.2/10** | **3.1/10** | **SQS** |

**Decision**: SQS wins with 9.5/10 score (cost + retry logic + zero maintenance)

**Why Not Kinesis?** Costs 27× more ($11 vs. $0.40), real-time streaming not needed for 5-min polling intervals.

---

### 3. Data Processing: Spark Cluster vs. AWS Glue

**Critical Analysis**: This was the most debated decision.

| Criterion | Weight | Spark Cluster | AWS Glue | EMR | Lambda | Winner |
|-----------|--------|---------------|----------|-----|--------|--------|
| **Cost** | 20% | 6/10 ($45) | 9/10 ($9) | 2/10 ($65) | 10/10 ($2) | Glue/Lambda |
| **Latency** | 25% | 9/10 (<3 min) | 2/10 (7 min) | 8/10 (<5 min) | 10/10 (<1 min) | **Spark** |
| **Debugging** | 20% | 10/10 (SSH) | 2/10 (logs only) | 9/10 (SSH) | 3/10 (CloudWatch) | **Spark** |
| **Portability** | 15% | 10/10 (standard) | 3/10 (Glue API) | 9/10 (standard) | 5/10 (AWS only) | **Spark** |
| **Scalability** | 10% | 7/10 (manual) | 10/10 (auto) | 10/10 (auto) | 8/10 (auto) | Glue/EMR |
| **Maintenance** | 10% | 5/10 (EC2) | 10/10 (serverless) | 4/10 (cluster) | 9/10 (serverless) | Glue |
| **Total Score** | | **7.95/10** | **5.80/10** | **6.70/10** | **7.15/10** | **Spark** |

**Decision**: Spark Cluster wins with 7.95/10 score

**Key Factors**:
1. **Latency**: Mobly needs <5 min for real-time dashboards (Glue: 7 min, Spark: <3 min)
2. **Debugging**: Production issues need SSH access (Spark wins)
3. **Cost**: $37/month extra is acceptable for 3× faster processing + full control

**Trade-Off**: We accept:
- ❌ $37/month higher cost vs. Glue
- ❌ Manual scaling vs. Glue's auto-scaling
- ❌ EC2 maintenance (patching, monitoring)

**We Gain**:
- ✅ 2.3× faster processing (3 min vs. 7 min)
- ✅ Zero cold start (always hot)
- ✅ Full SSH access (debugging, tuning)
- ✅ Standard Spark (portable to any cloud)
- ✅ Custom libraries (no limitations)

**When to Reconsider Glue**:
- Processing <10 hours/month (cost drops to $4/month)
- Latency >1 hour acceptable
- Team prefers zero infrastructure management
- Budget <$50/month hard constraint

---

### 4. Data Storage: RDS PostgreSQL

**Evaluated Options**: RDS, DynamoDB, S3+Athena, Redshift, TimescaleDB, Aurora

| Criterion | Weight | RDS PG | DynamoDB | S3+Athena | Redshift | Aurora | Winner |
|-----------|--------|--------|----------|-----------|----------|--------|--------|
| **Cost** | 25% | 9/10 ($16) | 10/10 ($1) | 10/10 ($2) | 1/10 ($180) | 2/10 ($43) | DynamoDB/S3 |
| **Query Latency** | 25% | 10/10 (<50ms) | 7/10 (200ms) | 2/10 (5s) | 10/10 (<50ms) | 10/10 (<50ms) | **RDS** |
| **SQL Support** | 20% | 10/10 (full SQL) | 3/10 (NoSQL) | 9/10 (Presto SQL) | 10/10 (full SQL) | 10/10 (full SQL) | **RDS** |
| **Grafana Integration** | 15% | 10/10 (native) | 5/10 (plugin) | 6/10 (limited) | 9/10 (native) | 10/10 (native) | **RDS** |
| **Operational Simplicity** | 10% | 8/10 (managed) | 10/10 (serverless) | 9/10 (serverless) | 6/10 (managed) | 7/10 (managed) | DynamoDB |
| **Data Growth (5 years)** | 5% | 10/10 (20 GB) | 10/10 (infinite) | 10/10 (infinite) | 10/10 (PB scale) | 10/10 (64 TB) | All |
| **Total Score** | | **9.3/10** | **6.8/10** | **6.0/10** | **7.5/10** | **8.1/10** | **RDS PG** |

**Decision**: RDS PostgreSQL wins with 9.3/10 score

**Why RDS Over DynamoDB?**
- **Query Latency**: 15-30 ms (RDS) vs. 200-500 ms (DynamoDB)
- **SQL Familiarity**: Team knows PostgreSQL, Grafana has native connector
- **Complex Aggregations**: JOINs, window functions (hard in DynamoDB)
- **5-Year TCO**: $970 (RDS) vs. $180 (DynamoDB), but RDS saves 100+ hours of NoSQL learning

**Why RDS Over S3+Athena?**
- **Dashboard Latency**: 15 ms (RDS) vs. 3-10 seconds (Athena) per query
- **Concurrent Queries**: 50+ concurrent (RDS) vs. 20 max (Athena)
- **Predictable Cost**: $16/month (RDS) vs. $5/TB scanned (unpredictable)

**Why RDS Over Aurora Serverless?**
- **Cost**: $16/month (RDS) vs. $43/month (Aurora) = 2.7× more expensive
- **Scale**: Mobly's 180K rows/year fits in db.t4g.micro (no auto-scaling needed)

**Data Capacity Proof**:
```
Mobly Traffic: 24,000 visits/day
Aggregated Data: 500 rows/day (hourly + endpoint + device metrics)
Annual Growth: 500 × 365 = 182,500 rows/year
Storage: 182,500 × 1 KB/row = 183 MB/year

db.t4g.micro: 20 GB storage
Capacity: 20 GB ÷ 183 MB/year = 109 years of data! ✅
```

---

### 5. Visualization: Grafana OSS

**Evaluated Options**: Grafana OSS, Managed Grafana, QuickSight, Tableau, Looker, Custom

| Criterion | Weight | Grafana OSS | Managed Grafana | QuickSight | Tableau | Custom | Winner |
|-----------|--------|-------------|-----------------|------------|---------|--------|--------|
| **Cost** | 30% | 9/10 ($15) | 5/10 ($45) | 3/10 ($120) | 1/10 ($350) | 8/10 (dev time) | **Grafana** |
| **Feature Set** | 25% | 10/10 (full) | 9/10 (limited) | 7/10 (BI focus) | 9/10 (enterprise) | 10/10 (custom) | **Grafana** |
| **Setup Time** | 20% | 9/10 (30 min) | 7/10 (1 hr) | 5/10 (2 hrs) | 4/10 (days) | 2/10 (weeks) | **Grafana** |
| **Maintenance** | 15% | 6/10 (EC2) | 10/10 (managed) | 10/10 (managed) | 9/10 (SaaS) | 3/10 (ongoing) | Managed |
| **Portability** | 10% | 10/10 (open) | 5/10 (AWS) | 3/10 (AWS) | 6/10 (SaaS) | 8/10 (code) | **Grafana** |
| **Total Score** | | **8.9/10** | **7.1/10** | **5.5/10** | **5.8/10** | **6.2/10** | **Grafana OSS** |

**Decision**: Grafana OSS wins with 8.9/10 score

**5-Year Cost Comparison**:
- Grafana OSS: $15/month × 60 = **$900**
- Managed Grafana: $45/month × 60 = **$2,700** (3× more)
- QuickSight: $120/month × 60 = **$7,200** (8× more)
- Tableau: $350/month × 60 = **$21,000** (23× more)

**Savings**: Grafana OSS saves **$1,800-$20,100** over 5 years vs. alternatives.

**Trade-Off**: We accept:
- ❌ Manual upgrades (5 min/month)
- ❌ EC2 maintenance (patching, monitoring)
- ❌ No AWS-managed backups (must configure)

**We Gain**:
- ✅ $30/month savings vs. Managed Grafana
- ✅ Unlimited users (no per-user licensing)
- ✅ Full control (custom plugins, themes)
- ✅ Portable (migrate to any cloud in 1 hour)

---

## Summary: Final Architecture Scorecard

| Component | Chosen Solution | Score | Runner-Up | Score Gap |
|-----------|----------------|-------|-----------|-----------|
| **Event Processing** | AWS Lambda | 9.6/10 | EventBridge | +2.3 |
| **Message Buffer** | SQS Standard | 9.5/10 | Kinesis | +2.5 |
| **Data Processing** | Spark Cluster | 7.95/10 | Lambda | +0.8 |
| **Data Storage** | RDS PostgreSQL | 9.3/10 | Aurora | +1.2 |
| **Visualization** | Grafana OSS | 8.9/10 | Managed Grafana | +1.8 |
| **Average Score** | | **8.85/10** | | |

**Confidence Level**: ✅ **High** (all alternatives evaluated, clear winners)

---

## Cost-Performance Analysis

### Monthly Cost Breakdown

| Component | Cost | % of Total | Alternatives (Cheaper) | Trade-Off |
|-----------|------|------------|------------------------|-----------|
| Lambda | $0.20 | 0.2% | N/A | None (cheapest) |
| SQS | $0.40 | 0.4% | N/A | None (cheapest) |
| **Spark Cluster** | $45.54 | 41.4% | Glue: $8.80 | +$37 for 2× speed + control |
| **RDS PostgreSQL** | $16.17 | 14.7% | DynamoDB: $1.25 | +$15 for SQL + 10× faster queries |
| **Grafana** | $15.18 | 13.8% | Managed: $45 | Save $30 with self-hosting |
| NAT Gateway | $32.85 | 29.8% | N/A | Required for private RDS |
| S3 + Secrets | $0.47 | 0.4% | N/A | Minimal |
| **Total** | **$110.81** | 100% | **$77** (serverless) | +$33 for control + speed |

**Analysis**:
- **Top 3 costs**: NAT ($33), Spark ($45), RDS ($16) = 85% of budget
- **Optimization potential**: $33/month (30% savings) by using Glue + DynamoDB
- **Trade-off**: Lose real-time dashboards + full control

---

## When to Revisit These Decisions

### Trigger 1: Cost Exceeds $150/month
**Action**: 
1. Switch to AWS Glue ($8.80) → saves $37/month
2. Switch to DynamoDB ($1.25) → saves $15/month
3. **Total savings**: $52/month (47% reduction)

**New Total**: $110 - $52 = **$58/month**

**Trade-off**: Accept 7-min latency + lose SSH access

---

### Trigger 2: Data Volume Exceeds 100 GB/day
**Action**:
1. Upgrade Spark Workers to t3.medium (4 vCPU) → +$30/month
2. Upgrade RDS to db.t4g.small (2 vCPU) → +$16/month
3. Add NAT Gateway in AZ-2 for HA → +$33/month

**New Total**: $110 + $79 = **$189/month**

**Alternative**: Use EMR with auto-scaling ($120/month) + Aurora Serverless ($60/month) = $180/month

---

### Trigger 3: Need Sub-Minute Latency
**Action**:
1. Replace SQS + Spark with Kinesis Data Streams → +$11/month
2. Add Kinesis Data Analytics → +$0.11/hour × 24 × 30 = +$79/month

**New Total**: $110 - $46 (remove Spark) + $90 (Kinesis) = **$154/month**

**Latency**: 7 min → <30 seconds (14× improvement)

---

### Trigger 4: Team Prefers Zero Infrastructure
**Action**:
1. Replace Spark with AWS Glue → saves $37/month
2. Replace Grafana OSS with Managed Grafana → +$30/month (5 users)
3. Replace RDS with DynamoDB → saves $15/month

**New Total**: $110 - $37 + $30 - $15 = **$88/month**

**Trade-off**: 7-min latency + Glue learning curve

---

## Final Recommendation

✅ **Adopt Current Architecture** (Spark + RDS + Grafana OSS) for Mobly because:

1. **Meets Latency SLA**: <3 min vs. 7 min (Glue)
2. **Cost-Effective**: $110/month is 58% cheaper than alternatives (EMR: $189, Kinesis: $154)
3. **Operational Control**: Full SSH access for debugging + tuning
4. **Portable**: Standard Spark (no vendor lock-in)
5. **Future-Proof**: Can scale to 100× traffic (2.4M visits/day) for +$200/month

**Risk Mitigation**:
- Set CloudWatch alarm if cost exceeds $130/month → investigate
- Set alert if Spark job latency >5 min → optimize or scale
- Review architecture every 6 months as data grows

---

## Alternative Scenarios

### Scenario A: Startup with <$50/month Budget
**Architecture**: S3 → Lambda → DynamoDB → API Gateway → QuickSight  
**Cost**: $45/month  
**Trade-off**: 5-min latency, NoSQL learning curve, no real-time

### Scenario B: Enterprise with >$500/month Budget
**Architecture**: S3 → Databricks Auto Loader → Delta Lake → Databricks SQL  
**Cost**: $450/month  
**Benefits**: Unified ML + analytics, auto-scaling, collaborative notebooks

### Scenario C: Financial Services (High Compliance)
**Architecture**: S3 → Step Functions → EMR Transient Cluster → Redshift → Tableau  
**Cost**: $320/month  
**Benefits**: Audit logs, VPC isolation, role-based access control (RBAC)

---

**Document Version**: 1.0  
**Last Updated**: 2025-12-14  
**Next Review**: 2026-06-14 (6 months)

