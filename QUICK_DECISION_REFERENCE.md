# Quick Decision Reference - DataLens Architecture

> **TL;DR**: Use Spark Cluster for real-time analytics (<5 min), AWS Glue for batch processing (>1 hr latency OK)

---

## 🎯 Quick Decision Trees

### Decision 1: Lambda vs. Alternatives

```
Do you need to react to S3 uploads in real-time?
├─ YES → Is latency <1 second required?
│         ├─ YES → Use Lambda ✅
│         └─ NO → Use EventBridge
└─ NO → Use scheduled job (AWS Batch or cron)
```

**Winner**: Lambda ($0.20/month, <500ms latency)

---

### Decision 2: SQS vs. Alternatives

```
Do you need to decouple S3 events from processing?
├─ YES → Do you need real-time streaming (<1 second)?
│         ├─ YES → Use Kinesis Data Streams ($11/month)
│         └─ NO → Use SQS Standard ✅ ($0.40/month)
└─ NO → Process directly (not recommended)
```

**Winner**: SQS Standard (batching + retry + DLQ for $0.40/month)

---

### Decision 3: Spark vs. Glue (Most Critical)

```
What's your required data freshness?
├─ <5 minutes (real-time dashboards)
│   ├─ Data volume <1 GB/day?
│   │   ├─ YES → Use Lambda directly ($2/month)
│   │   └─ NO → Use Spark Cluster ✅ ($45/month)
│   └─ Data volume >100 GB/day?
│       └─ Use Spark Cluster + scale workers ($75/month)
│
├─ 5 minutes - 1 hour (near real-time)
│   └─ Use Spark Cluster ✅ ($45/month)
│
└─ >1 hour (batch processing)
    ├─ Processing <10 hours/month?
    │   └─ Use AWS Glue ($8.80/month)
    └─ Processing >10 hours/month?
        └─ Use Spark Cluster ($45/month)
```

**For Mobly (24K visits/day, <5 min latency)**: Spark Cluster wins ✅

**When Glue Wins**: Batch processing, latency >1 hour, processing <10 hrs/month

---

### Decision 4: RDS vs. Alternatives

```
What's your data volume and query complexity?
├─ <10 GB, simple key-value lookups
│   └─ Use DynamoDB ($1/month)
│
├─ 10-500 GB, complex SQL queries (JOINs, aggregations)
│   ├─ Query latency <100ms required?
│   │   └─ Use RDS PostgreSQL ✅ ($16/month)
│   └─ Query latency >1 second OK?
│       └─ Use S3 + Athena ($2/month)
│
└─ >500 GB, data warehouse workloads
    ├─ Budget <$100/month?
    │   └─ Use S3 + Athena ($20/month)
    └─ Budget >$100/month?
        └─ Use Redshift Serverless ($180/month)
```

**For Mobly (~100 GB/year, SQL queries)**: RDS PostgreSQL wins ✅

---

### Decision 5: Grafana vs. Alternatives

```
How many users need dashboards?
├─ 1-10 users, self-service setup
│   └─ Use Grafana OSS ✅ ($15/month)
│
├─ 10-50 users, need SSO + RBAC
│   ├─ Budget <$100/month?
│   │   └─ Use Grafana OSS + Auth proxy ($15/month)
│   └─ Budget >$100/month?
│       └─ Use Managed Grafana ($90/month)
│
└─ 50+ users, enterprise BI features
    └─ Use QuickSight ($240+/month)
```

**For Mobly (5 users)**: Grafana OSS wins ✅ (saves $30/month vs. Managed)

---

## 📊 Cost vs. Performance Matrix

| Architecture | Cost/Month | Latency | Best For |
|--------------|------------|---------|----------|
| **Lambda Only** | $18 | <5 sec | Files <10 MB, simple transforms |
| **AWS Glue + DynamoDB** | $45 | 5-7 min | Batch processing, <10 hrs/month |
| **Spark + RDS + Grafana** ✅ | $110 | <3 min | Real-time dashboards, continuous processing |
| **Kinesis + Analytics** | $154 | <30 sec | High-frequency streaming (>1K events/min) |
| **EMR + Redshift** | $245 | <5 min | Data warehouse, >500 GB/day |
| **Databricks Lakehouse** | $450+ | <1 min | ML + analytics, enterprise scale |

---

## 🔥 Key Insights (Why Each Technology Won)

### 1. Lambda Won Because:
- ✅ **Cheapest**: $0.20/month vs. $15/month (EC2)
- ✅ **Fastest**: <500ms trigger latency
- ✅ **Zero Maintenance**: No servers to manage
- ❌ Rejected EC2: 75× more expensive for same task

### 2. SQS Won Because:
- ✅ **Batching**: Process 10 files at once (efficient)
- ✅ **Built-in Retry**: DLQ after 3 failures
- ✅ **Dirt Cheap**: $0.40/month for 2,880 messages
- ❌ Rejected Kinesis: 27× more expensive, streaming not needed

### 3. Spark Cluster Won Because:
- ✅ **Latency**: <3 min vs. 7 min (Glue cold start)
- ✅ **Control**: Full SSH access for debugging
- ✅ **Portability**: Standard Spark (no vendor lock-in)
- ⚖️ **Trade-off**: +$37/month vs. Glue (acceptable for real-time dashboards)

### 4. RDS PostgreSQL Won Because:
- ✅ **Query Speed**: 15-30 ms vs. 200 ms (DynamoDB) vs. 3-10s (Athena)
- ✅ **SQL Familiarity**: Team knows PostgreSQL, Grafana native support
- ✅ **Capacity**: 20 GB = 109 years of Mobly data!
- ❌ Rejected DynamoDB: NoSQL learning curve, slower queries
- ❌ Rejected Aurora: 3× more expensive, overkill for Mobly's scale

### 5. Grafana OSS Won Because:
- ✅ **Cost**: $15/month vs. $45 (Managed) vs. $120 (QuickSight)
- ✅ **Unlimited Users**: No per-user licensing
- ✅ **Portability**: Migrate to any cloud in 1 hour
- ⚖️ **Trade-off**: Manual upgrades (5 min/month)

---

## 🚨 Red Flags (When to Switch)

### Switch to AWS Glue if:
1. ❌ Processing drops below 10 hours/month (cost: $8.80)
2. ❌ Latency >1 hour is acceptable
3. ❌ Team prefers zero infrastructure management
4. ❌ Budget constraint: must stay under $50/month

### Switch to DynamoDB if:
1. ❌ Data grows beyond 500 GB (cost: $125/month in RDS)
2. ❌ Need multi-region replication (global tables)
3. ❌ Query patterns are simple key-value lookups
4. ❌ Grafana not primary visualization tool

### Switch to Managed Grafana if:
1. ❌ Team size exceeds 20 users (complex SSO setup)
2. ❌ No DevOps resources to manage EC2 instance
3. ❌ Need workspace isolation (multi-tenant)
4. ❌ Budget increases to >$200/month (can absorb extra cost)

---

## 💡 One-Sentence Summaries

| Component | Why Chosen | One-Sentence Rationale |
|-----------|------------|------------------------|
| **Lambda** | $0.20/month, <500ms | Cheapest way to trigger on S3 uploads with sub-second latency. |
| **SQS** | $0.40/month, batching | Enables batch processing (10 files at once) with built-in retry for $0.40/month. |
| **Spark** | <3 min, full control | Only solution that delivers <5 min latency with full SSH access for $110/month. |
| **RDS** | 15-30 ms queries | PostgreSQL delivers 10× faster queries than DynamoDB with SQL familiarity. |
| **Grafana** | $15/month, unlimited users | Self-hosting saves $30/month vs. Managed Grafana with no user limits. |

---

## 🎓 Learning from Our Decisions

### Principle 1: "Latency Drives Architecture"
- **Real-time (<5 min)** → Spark Cluster (always hot)
- **Near real-time (5 min - 1 hr)** → Spark or EMR
- **Batch (>1 hr)** → AWS Glue (cheapest)

### Principle 2: "Cost vs. Control Trade-Off"
- **More Control** → Higher Cost (Spark: $110/month)
- **Less Control** → Lower Cost (Glue: $45/month)
- **Sweet Spot**: Pay $65/month more for 2× speed + full SSH access

### Principle 3: "SQL Beats NoSQL for Analytics"
- **RDS PostgreSQL**: Complex aggregations in 15-30 ms
- **DynamoDB**: Simple lookups fast, aggregations slow (200+ ms)
- **Athena**: Cheapest storage, but 3-10 second query latency

### Principle 4: "Open Source = Portability"
- **Grafana OSS**: Migrate to any cloud in 1 hour (export JSON)
- **Managed Grafana**: AWS-locked, complex export
- **QuickSight**: AWS-only, no export path

### Principle 5: "Always-On Beats Cold Start"
- **Spark Cluster** (always-on): <3 min latency
- **AWS Glue** (cold start): 7 min latency (1-2 min cluster init)
- **Trade-off**: Pay $37/month more to eliminate 5-min wait

---

## 📈 Scaling Path

### Current: 24K visits/day ($110/month)
```
S3 → Lambda → SQS → Spark (t3.small × 3) → RDS (t4g.micro) → Grafana
```

### 10× Scale: 240K visits/day ($190/month)
```
S3 → Lambda → SQS → Spark (t3.medium × 3) → RDS (t4g.small) → Grafana
              ↓
       (Add 2 more workers)
```

### 100× Scale: 2.4M visits/day ($450/month)
```
S3 → Lambda → SQS → EMR (auto-scale 3-10 nodes) → Aurora Serverless → Managed Grafana
              ↓
       (Switch to EMR for auto-scaling)
```

---

## 🏁 Final Verdict

**For Mobly (24K visits/day, real-time dashboards)**:

✅ **Adopt**: Spark + RDS + Grafana OSS = $110/month  
❌ **Reject**: Glue + DynamoDB = $45/month (too slow: 7 min latency)  
❌ **Reject**: Kinesis + Analytics = $154/month (overkill for 5-min polling)  

**Confidence**: ✅ **High** (all alternatives evaluated, clear winner)

---

**Document**: Quick Decision Reference  
**Version**: 1.0  
**Last Updated**: 2025-12-14

**Full Details**: See `SPARK_SERVERLESS_ARCHITECTURE.md` (1065 lines) and `TECHNOLOGY_DECISIONS.md` (298 lines)

