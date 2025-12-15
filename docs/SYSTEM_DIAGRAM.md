# DataLens System Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                 AKAMAI EDGE NETWORK                                      │
│                              (Global CDN Infrastructure)                                 │
│                                                                                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐               │
│  │ Edge US  │  │ Edge EU  │  │ Edge APAC│  │ Edge LATAM│  │ Edge ME  │               │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘               │
│       │             │             │             │             │                         │
│       └─────────────┴─────────────┴─────────────┴─────────────┘                         │
│                              │                                                           │
│                              │ DataStream2 (Configured)                                  │
│                              ▼                                                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                               │
                               │ Every 5 minutes
                               │ Gzip compressed logs
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                              AWS S3 STORAGE LAYER                                        │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  s3://datalens-akamai-logs/                                                        │ │
│  │  ├── logs/                          ◄── Raw Akamai logs (source)                  │ │
│  │  │   └── 2025/                                                                     │ │
│  │  │       └── 12/                                                                   │ │
│  │  │           └── 13/                                                               │ │
│  │  │               ├── 00/ ──► 123456_20251213_0005_001.log.gz (10-100MB each)     │ │
│  │  │               ├── 01/ ──► 123456_20251213_0105_001.log.gz                     │ │
│  │  │               └── 23/                                                           │ │
│  │  │                                                                                  │ │
│  │  └── processed/                     ◄── Processed data (Parquet)                  │ │
│  │      └── 2025/12/13/ ──► Columnar format, compressed                             │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                               │
                               │ S3A FileSystem (Hadoop)
                               │ Parallel reads
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                         KUBERNETES CLUSTER (EKS/GKE/AKS)                                │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │                            NAMESPACE: datalens                                     │ │
│  │                                                                                    │ │
│  │  ┌──────────────────────────────────────────────────────────────────────────────┐ │ │
│  │  │                    SPARK PROCESSING LAYER                                     │ │
│  │  │                                                                                │ │ │
│  │  │  ┌────────────────────────────────────────────────────────────────┐          │ │ │
│  │  │  │  Spark Operator (GoogleCloudPlatform/spark-on-k8s-operator)   │          │ │ │
│  │  │  │  • Manages Spark Application lifecycle                         │          │ │ │
│  │  │  │  • Schedules driver and executor pods                          │          │ │ │
│  │  │  │  • Handles failures and restarts                               │          │ │ │
│  │  │  └────────────────────────────────────────────────────────────────┘          │ │ │
│  │  │                              │                                                 │ │ │
│  │  │                              ▼                                                 │ │ │
│  │  │  ┌────────────────────────────────────────────────────────────────┐          │ │ │
│  │  │  │  Spark Driver Pod                                               │          │ │ │
│  │  │  │  ┌──────────────────────────────────────────────────────────┐  │          │ │ │
│  │  │  │  │  s3_processor.py                                          │  │          │ │ │
│  │  │  │  │  • Reads S3 paths (partition-aware)                      │  │          │ │ │
│  │  │  │  │  • Parses 70-field Akamai format                         │  │          │ │ │
│  │  │  │  │  • Applies transformations                                │  │          │ │ │
│  │  │  │  │  • Coordinates executors                                  │  │          │ │ │
│  │  │  │  │  • Manages DAG execution                                  │  │          │ │ │
│  │  │  │  └──────────────────────────────────────────────────────────┘  │          │ │ │
│  │  │  │  Resources: 2 CPU, 4GB RAM                                      │          │ │ │
│  │  │  └────────────────────────────────────────────────────────────────┘          │ │ │
│  │  │                              │                                                 │ │ │
│  │  │            ┌─────────────────┼─────────────────┬─────────────────┐           │ │ │
│  │  │            ▼                 ▼                 ▼                 ▼            │ │ │
│  │  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐    │ │ │
│  │  │  │  Executor 1  │  │  Executor 2  │  │  Executor 3  │  │  Executor 4  │    │ │ │
│  │  │  │  2C / 4GB    │  │  2C / 4GB    │  │  2C / 4GB    │  │  2C / 4GB    │    │ │ │
│  │  │  │              │  │              │  │              │  │              │    │ │ │
│  │  │  │  • Parse     │  │  • Parse     │  │  • Parse     │  │  • Parse     │    │ │ │
│  │  │  │  • Transform │  │  • Transform │  │  • Transform │  │  • Transform │    │ │ │
│  │  │  │  • Aggregate │  │  • Aggregate │  │  • Aggregate │  │  • Aggregate │    │ │ │
│  │  │  └──────────────┘  └──────────────┘  └──────────────┘  └──────────────┘    │ │ │
│  │  │                                                                                │ │ │
│  │  │  Auto-scaling: 4-16 executors based on workload                              │ │ │
│  │  └────────────────────────────────────────────────────────────────────────────────┘ │ │
│  │                              │                                                       │ │
│  │                              │ Write to multiple sinks                              │ │
│  │                              │                                                       │ │
│  │              ┌───────────────┼───────────────┬──────────────────┐                  │ │
│  │              ▼               ▼               ▼                  ▼                   │ │
│  │  ┌────────────────┐ ┌─────────────────┐ ┌────────────────┐ ┌──────────────┐     │ │
│  │  │  KAFKA         │ │  TIMESCALEDB    │ │  MINIO         │ │  ALERTS      │     │ │
│  │  │  (Streaming)   │ │  (Queryable)    │ │  (Archive)     │ │  (PagerDuty) │     │ │
│  │  └────────────────┘ └─────────────────┘ └────────────────┘ └──────────────┘     │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  KAFKA CLUSTER (Bitnami Helm Chart)                                               │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐                                        │ │
│  │  │ Broker 1 │  │ Broker 2 │  │ Broker 3 │  Replication Factor: 2                │ │
│  │  └──────────┘  └──────────┘  └──────────┘                                        │ │
│  │                                                                                    │ │
│  │  Topics:                                                                           │ │
│  │  • akamai-raw-logs (6 partitions)        ──► Raw parsed logs                     │ │
│  │  • akamai-processed-metrics (3 partitions) ──► Aggregated metrics                │ │
│  │  • akamai-alerts (1 partition)           ──► Anomaly alerts                      │ │
│  │                                                                                    │ │
│  │  Retention: 7 days, Compression: snappy                                           │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  TIMESCALEDB (Timescale Helm Chart)                                               │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │ │
│  │  │  PostgreSQL 14 with TimescaleDB Extension                                   │  │ │
│  │  │                                                                               │  │ │
│  │  │  Tables:                                                                      │  │ │
│  │  │  ┌────────────────────────────────────────────────────────────────────────┐ │  │ │
│  │  │  │  akamai_logs (Hypertable)                                              │ │  │ │
│  │  │  │  • Partitioned by request_timestamp (1 day chunks)                     │ │  │ │
│  │  │  │  • Automatic compression after 7 days (10:1 ratio)                     │ │  │ │
│  │  │  │  • Indexes: time, country, status, cache                               │ │  │ │
│  │  │  │  • 70+ columns matching Akamai schema                                  │ │  │ │
│  │  │  └────────────────────────────────────────────────────────────────────────┘ │  │ │
│  │  │                                                                               │  │ │
│  │  │  Continuous Aggregates (Real-time materialized views):                       │  │ │
│  │  │  ┌────────────────────────────────────────────────────────────────────────┐ │  │ │
│  │  │  │  akamai_hourly_metrics                                                 │ │  │ │
│  │  │  │  • Auto-updated every 5 minutes                                        │ │  │ │
│  │  │  │  • Pre-aggregated by country, hour                                     │ │  │ │
│  │  │  │  • Fast queries for dashboards                                         │ │  │ │
│  │  │  └────────────────────────────────────────────────────────────────────────┘ │  │ │
│  │  │                                                                               │  │ │
│  │  │  Performance: 100K inserts/sec, sub-second queries on 1B+ rows              │  │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  MINIO (S3-Compatible Storage)                                                    │ │
│  │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐                         │ │
│  │  │  Node 1  │  │  Node 2  │  │  Node 3  │  │  Node 4  │  Distributed mode       │ │
│  │  └──────────┘  └──────────┘  └──────────┘  └──────────┘                         │ │
│  │                                                                                    │ │
│  │  Buckets:                                                                          │ │
│  │  • processed/    ──► Parquet files (columnar, Snappy compressed)                 │ │
│  │  • archived/     ──► Long-term storage                                            │ │
│  │  • backups/      ──► TimescaleDB exports                                          │ │
│  │                                                                                    │ │
│  │  Erasure Coding: 4+2 (survives 2 disk failures)                                   │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
│  ┌────────────────────────────────────────────────────────────────────────────────────┐ │
│  │  GRAFANA (Visualization & Alerting)                                               │ │
│  │  ┌─────────────────────────────────────────────────────────────────────────────┐  │ │
│  │  │  Data Sources:                                                               │  │ │
│  │  │  • TimescaleDB (PostgreSQL) ──► Primary for dashboards                      │  │ │
│  │  │  • Kafka (via plugin)       ──► Real-time streaming                         │  │ │
│  │  │  • Prometheus (optional)    ──► Infrastructure metrics                      │  │ │
│  │  │                                                                               │  │ │
│  │  │  Dashboards:                                                                  │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │  📊 Performance Analytics                                             │  │  │ │
│  │  │  │     • Request rate (req/sec)                                          │  │  │ │
│  │  │  │     • TTFB percentiles (p50, p95, p99)                                │  │  │ │
│  │  │  │     • Throughput trends                                               │  │  │ │
│  │  │  │     • Error rates                                                     │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────────────────┘  │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │  🛡️  Security Monitoring                                              │  │  │ │
│  │  │  │     • WAF rule triggers                                               │  │  │ │
│  │  │  │     • Bot detection                                                   │  │  │ │
│  │  │  │     • DDoS indicators                                                 │  │  │ │
│  │  │  │     • Blocked requests                                                │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────────────────┘  │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │  🌍 Geographic Insights                                               │  │  │ │
│  │  │  │     • World map (request density)                                     │  │  │ │
│  │  │  │     • Top countries/cities                                            │  │  │ │
│  │  │  │     • Latency by region                                               │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────────────────┘  │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │  📦 Cache Efficiency                                                  │  │  │ │
│  │  │  │     • Hit ratio trends                                                │  │  │ │
│  │  │  │     • Origin offload                                                  │  │  │ │
│  │  │  │     • Byte savings                                                    │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────────────────┘  │  │ │
│  │  │  ┌───────────────────────────────────────────────────────────────────────┐  │  │ │
│  │  │  │  ⚡ EdgeWorkers Analytics                                            │  │  │ │
│  │  │  │     • Execution times                                                 │  │  │ │
│  │  │  │     • Error rates                                                     │  │  │ │
│  │  │  │     • Resource usage                                                  │  │  │ │
│  │  │  └───────────────────────────────────────────────────────────────────────┘  │  │ │
│  │  │                                                                               │  │ │
│  │  │  Alerting:                                                                    │  │ │
│  │  │  • Email, Slack, PagerDuty integration                                       │  │ │
│  │  │  • Alert rules: Error rate, TTFB, throughput                                │  │ │
│  │  └─────────────────────────────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────────────────────────────┘ │
│                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                               │
                               │ Kubernetes Ingress (HTTPS)
                               │ Load Balancer (ALB/NLB)
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                   END USERS                                              │
│                                                                                          │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                  │
│  │   DevOps    │  │  Analytics  │  │  Business   │  │  Executives │                  │
│  │   Engineer  │  │   Team      │  │   Users     │  │             │                  │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘                  │
│        │                 │                 │                 │                          │
│        │                 │                 │                 │                          │
│        ▼                 ▼                 ▼                 ▼                          │
│  ┌────────────────────────────────────────────────────────────────┐                    │
│  │           https://grafana.datalens.company.com                 │                    │
│  │  • Real-time dashboards                                        │                    │
│  │  • Custom queries                                              │                    │
│  │  • Alert notifications                                         │                    │
│  │  • Report generation                                           │                    │
│  └────────────────────────────────────────────────────────────────┘                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘


DATA FLOW SUMMARY:
==================

1. Akamai Edge → S3: Every 5 minutes, gzipped logs
2. Spark reads S3: Parallel reads, partition-aware
3. Spark processes: Parse 70 fields, transform, enrich
4. Spark writes:
   - Kafka: Real-time streaming (7 day retention)
   - TimescaleDB: Queryable storage (90 day retention)
   - MinIO: Long-term archive (unlimited)
5. Grafana queries: TimescaleDB for dashboards
6. Users access: HTTPS via Ingress, authenticated

PERFORMANCE CHARACTERISTICS:
============================

Throughput:  1-12 GB/min (scales with executors)
Latency:     10-15 minutes (batch), 5 min (streaming)
Query Time:  <1 second for 90 days of data
Scalability: 10GB to 10TB+ per day
Cost:        $38 per TB processed

FAULT TOLERANCE:
================

• Kubernetes: Auto-restart failed pods
• Spark: Checkpoint and retry failed tasks
• Kafka: Replicated messages (2x)
• TimescaleDB: Streaming replication
• MinIO: Erasure coding (survives 2 failures)
• S3: 99.999999999% durability (source of truth)

MONITORING:
===========

• Prometheus: Infrastructure metrics
• Grafana: Application metrics
• Kubernetes: Pod health checks
• Spark: Job execution metrics
• TimescaleDB: Query performance
• Kafka: Consumer lag, throughput

SECURITY:
=========

• TLS 1.2+: All connections encrypted
• RBAC: Kubernetes role-based access
• IAM: AWS roles for S3 access (no keys)
• Secrets: Kubernetes Secrets for credentials
• Network Policies: Pod-to-pod restrictions
• Audit Logs: All access tracked
```

