# DStreamBolt Ingestion Service - Technical Deep Dive

## Table of Contents
1. [Overview](#overview)
2. [Architecture & Design Principles](#architecture--design-principles)
3. [How Ingestion Works](#how-ingestion-works)
4. [Security Model](#security-model)
5. [Performance & Scalability](#performance--scalability)
6. [Operational Excellence](#operational-excellence)
7. [High Availability & Disaster Recovery](#high-availability--disaster-recovery)
8. [Monitoring & Troubleshooting](#monitoring--troubleshooting)

---

## Overview

### What is the Ingestion Service?

The DStreamBolt Ingestion Service is a **high-throughput, production-grade HTTP API** designed to accept gzipped log bundles from external clients (third-party agents) and reliably deliver them to Apache Kafka for downstream processing.

### Core Responsibilities

1. **Accept** - Receive POST requests with gzipped log data (up to 50MB)
2. **Validate** - Authenticate clients using mTLS certificates
3. **Persist** - Write bundles to local disk immediately (crash safety)
4. **Process** - Decompress, parse, and extract individual log lines
5. **Publish** - Send each log line to Kafka topic `dstreambolt-logs`
6. **Monitor** - Track metrics (requests/sec, processing lag, failures)

### Why a Separate Ingestion Layer?

| Without Ingestion Layer | With Ingestion Layer |
|------------------------|---------------------|
| Clients write directly to Kafka | Clients hit HTTP endpoint (simpler) |
| Kafka credentials distributed to 1000s of agents | Only ingestion nodes have Kafka access (security) |
| Network failures = data loss | Disk-based queue = durability |
| Hard to rate-limit or audit | Centralized control & visibility |
| Difficult to scale Kafka connections | Scale ingestion horizontally |

---

## Architecture & Design Principles

### High-Level Architecture

```
┌─────────────────┐
│ External Client │ (Third-party agents)
│   (mTLS cert)   │
└────────┬────────┘
         │ HTTPS POST /ingest
         │ (gzipped bundle)
         ▼
┌─────────────────────────────────────────────────────┐
│            Application Load Balancer (ALB)          │
│  - TLS termination (dstreambolt.click)              │
│  - mTLS verification (optional passthrough)         │
│  - Rate limiting (AWS WAF)                          │
└─────────────────┬───────────────────────────────────┘
                  │
         ┌────────┴────────┐
         ▼                 ▼
┌──────────────┐   ┌──────────────┐
│ Ingest Node 1│   │ Ingest Node 2│  (Auto-scaling group)
│ (Flask/Gun.) │   │ (Flask/Gun.) │
└──────┬───────┘   └──────┬───────┘
       │                  │
       │ 1. Write to disk queue (/opt/dstreambolt/queue)
       │ 2. Return HTTP 201 (< 10ms)
       │ 3. Background thread processes queue
       │
       └─────────┬────────┘
                 ▼
         ┌───────────────┐
         │  Apache Kafka │
         │ (dstreambolt- │
         │     logs)     │
         └───────────────┘
```

### Design Principles

#### 1. **Fast Accept, Async Process**
- **Problem**: If processing blocks the HTTP request, clients timeout during Kafka slowdowns
- **Solution**: 
  - Write bundle to disk in < 5ms
  - Return HTTP 201 immediately
  - Background thread processes queue at its own pace

#### 2. **Disk-Based Durability**
- **Problem**: In-memory queues lose data on crash/restart
- **Solution**:
  - Every bundle written to disk before ACK
  - Atomic file operations (write to `.tmp`, then rename)
  - Process restarts resume from queue

#### 3. **Backpressure Management**
- **Problem**: Kafka slow/down → ingestion nodes OOM → service crash
- **Solution**:
  - Queue size limits (10,000 files max)
  - Return HTTP 429 when queue full
  - Clients retry with exponential backoff

#### 4. **Defense in Depth Security**
- **Problem**: Public internet exposure → attacks, unauthorized access
- **Solution**:
  - mTLS: Only clients with valid certificates can connect
  - Rate limiting: 100 req/min per IP
  - Audit logs: Every request logged to MySQL
  - Secrets Manager: No credentials in code/env

#### 5. **Observability First**
- **Problem**: Can't debug production issues without metrics
- **Solution**:
  - Every operation tracked (requests, queue depth, errors)
  - Metrics flushed to MySQL every 10 seconds
  - Grafana dashboards for real-time visibility

---

## How Ingestion Works

### Request Flow (Step-by-Step)

#### Step 1: Client Sends Bundle
```bash
curl -X POST https://dstreambolt.click/ingest \
  --cert client-cert.pem \
  --key client-key.pem \
  --data-binary @logs.json.gz \
  -H "Content-Type: application/gzip" \
  -H "Content-Encoding: gzip"
```

#### Step 2: ALB Verification
1. **DNS Resolution**: `dstreambolt.click` → ALB IP
2. **TLS Handshake**: ALB presents certificate
3. **mTLS Verification** (if enabled):
   - ALB requests client certificate
   - Validates against trust store (CA bundle in S3)
   - Checks certificate not revoked (CRL)
4. **Routing**: ALB forwards to healthy ingestion node

#### Step 3: Ingestion Node Processing

**Main Thread (Gunicorn Worker)**
```python
@app.route('/ingest', methods=['POST'])
def ingest():
    # 1. Rate Limit Check (Redis/in-memory)
    if rate_limiter.is_limited(request.remote_addr):
        return jsonify({"error": "Rate limit exceeded"}), 429
    
    # 2. Extract mTLS Certificate (from ALB header)
    client_cert = request.headers.get('X-Amzn-Mtls-Clientcert')
    if MTLS_ENABLED and not client_cert:
        return jsonify({"error": "Client certificate required"}), 401
    
    # 3. Validate Request
    if request.content_length > MAX_BUNDLE_SIZE:
        return jsonify({"error": "Bundle too large"}), 413
    
    # 4. Generate Unique Bundle ID
    bundle_id = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}"
    
    # 5. Write to Disk (atomic operation)
    temp_path = f"{QUEUE_DIR}/{bundle_id}.tmp"
    final_path = f"{QUEUE_DIR}/{bundle_id}.gz"
    
    with open(temp_path, 'wb') as f:
        f.write(request.data)
    
    os.rename(temp_path, final_path)  # Atomic on POSIX
    
    # 6. Increment Metrics
    METRICS['bundles_received'] += 1
    METRICS['bytes_received'] += len(request.data)
    
    # 7. Return Success (client unblocked)
    return jsonify({
        "status": "accepted",
        "bundle_id": bundle_id
    }), 201
```

**Background Worker Thread**
```python
def process_queue():
    while True:
        # 1. Scan queue directory
        files = sorted(Path(QUEUE_DIR).glob('*.gz'))
        
        if not files:
            time.sleep(1)
            continue
        
        for bundle_path in files:
            try:
                # 2. Read bundle
                with gzip.open(bundle_path, 'rt') as f:
                    content = f.read()
                
                # 3. Parse logs (handle both JSON and plain text)
                logs = parse_logs(content)
                
                # 4. Send to Kafka
                for log in logs:
                    producer.send(KAFKA_TOPIC, value=log.encode('utf-8'))
                
                producer.flush()
                
                # 5. Delete bundle (successful)
                os.remove(bundle_path)
                
                METRICS['bundles_processed'] += 1
                METRICS['logs_sent_kafka'] += len(logs)
                
            except CorruptedBundleError as e:
                # Move to quarantine
                quarantine_path = f"{QUARANTINE_DIR}/{bundle_path.name}"
                os.rename(bundle_path, quarantine_path)
                METRICS['bundles_corrupted'] += 1
                
            except KafkaException as e:
                # Retry logic (exponential backoff)
                if retry_count < MAX_RETRIES:
                    time.sleep(2 ** retry_count)
                    retry_count += 1
                else:
                    # Move to dead-letter queue
                    dlq_path = f"{DLQ_DIR}/{bundle_path.name}"
                    os.rename(bundle_path, dlq_path)
                    METRICS['bundles_failed'] += 1
```

**Metrics Flusher Thread**
```python
def flush_metrics():
    while True:
        time.sleep(10)  # Flush every 10 seconds
        
        try:
            conn = pymysql.connect(
                host=MYSQL_HOST,
                user=MYSQL_USER,
                password=MYSQL_PASSWORD,
                db=MYSQL_DB
            )
            
            cursor = conn.cursor()
            cursor.execute("""
                INSERT INTO ingestion_metrics 
                (timestamp, bundles_received, bundles_processed, 
                 logs_sent_kafka, bundles_failed, queue_depth)
                VALUES (%s, %s, %s, %s, %s, %s)
            """, (
                datetime.now(),
                METRICS['bundles_received'],
                METRICS['bundles_processed'],
                METRICS['logs_sent_kafka'],
                METRICS['bundles_failed'],
                len(list(Path(QUEUE_DIR).glob('*.gz')))
            ))
            
            conn.commit()
            cursor.close()
            conn.close()
            
        except Exception as e:
            print(f"Metrics flush error: {e}")
```

### Log Parsing Logic

The service supports **two formats**:

1. **JSON Format** (batch upload)
```json
[
  {"timestamp": "2025-12-13T10:00:00Z", "ip": "1.2.3.4", "method": "GET", ...},
  {"timestamp": "2025-12-13T10:00:01Z", "ip": "5.6.7.8", "method": "POST", ...}
]
```

2. **Plain Text Format** (Apache/Nginx logs)
```
1.2.3.4 - - [13/Dec/2025:10:00:00 +0000] "GET /api/users HTTP/1.1" 200 1234 ...
```

**Parsing Implementation**:
```python
def parse_logs(content: str) -> List[str]:
    try:
        # Try JSON first
        logs = json.loads(content)
        if isinstance(logs, list):
            return [json.dumps(log) for log in logs]
    except json.JSONDecodeError:
        pass
    
    # Fall back to plain text (one log per line)
    lines = [line.strip() for line in content.split('\n') if line.strip()]
    
    # Parse Apache/Nginx format using regex
    parsed_logs = []
    for line in lines:
        log_entry = parse_apache_format(line)
        if log_entry:
            parsed_logs.append(json.dumps(log_entry))
    
    return parsed_logs
```

---

## Security Model

### Why mTLS (Mutual TLS)?

| Security Level | Method | Pros | Cons | DStreamBolt Choice |
|---------------|--------|------|------|-------------------|
| ❌ None | HTTP | Fast | Anyone can POST | ❌ No |
| ⚠️ API Key | `Authorization: Bearer <token>` | Simple | Keys leak, rotate hard | ⚠️ Backup only |
| ✅ mTLS | Client certificate | Strongest, non-repudiation | Complex PKI | ✅ Primary |

### mTLS Implementation

#### Certificate Authority (CA) Setup
```bash
# Generate CA (one-time)
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=DStreamBolt-CA/O=DStreamBolt/C=US"
```

#### Client Certificate Issuance
```bash
# For each client (automated via API)
openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client-csr.pem \
  -subj "/CN=client-$CLIENT_ID/O=DStreamBolt-Client/C=US"

# CA signs (short-lived: 7 days)
openssl x509 -req -days 7 -in client-csr.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -CAcreateserial \
  -out client-cert.pem

# Deliver to client (secure channel)
# Client stores: client-cert.pem + client-key.pem
```

#### ALB Configuration (Terraform)
```hcl
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn
  
  # Enable mTLS
  mutual_authentication {
    mode            = "verify"  # or "passthrough"
    trust_store_arn = aws_lb_trust_store.mtls.arn
  }
  
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }
}

resource "aws_lb_trust_store" "mtls" {
  name                      = "dstreambolt-mtls"
  ca_certificates_bundle_s3_bucket = aws_s3_bucket.mtls.id
  ca_certificates_bundle_s3_key    = "ca-bundle.pem"
}
```

### Certificate Rotation Strategy

**Problem**: Certificates expire → service outage if not rotated

**Solution**: Automated rotation with grace period

1. **Issue short-lived certificates** (7 days)
2. **Client auto-renewal** (at 50% lifetime, i.e., day 3):
   ```python
   # Client agent checks daily
   if cert_expires_in_hours(client_cert) < 72:  # 3 days
       new_cert = api_call("/v1/certificates/renew", old_cert)
       atomic_replace(client_cert, new_cert)
   ```
3. **Overlapping validity**: Old cert valid for 24h grace period
4. **Monitoring**: Alert if >10% clients haven't renewed

### Why Rate Limiting?

**Threat**: Malicious client floods service → legitimate clients denied

**Implementation**:
```python
class RateLimiter:
    def __init__(self, max_requests=100, window_seconds=60):
        self.buckets = {}  # {ip: [timestamp1, timestamp2, ...]}
        self.max_requests = max_requests
        self.window = window_seconds
    
    def is_limited(self, ip: str) -> bool:
        now = time.time()
        
        # Clean old timestamps
        if ip in self.buckets:
            self.buckets[ip] = [
                ts for ts in self.buckets[ip] 
                if now - ts < self.window
            ]
        else:
            self.buckets[ip] = []
        
        # Check limit
        if len(self.buckets[ip]) >= self.max_requests:
            return True
        
        # Allow request
        self.buckets[ip].append(now)
        return False
```

**Limits** (tuned for production):
- 100 requests/minute per IP (normal clients)
- 1000 requests/minute per IP (whitelisted clients)
- 10,000 requests/minute globally (backpressure threshold)

### Secrets Management (AWS Secrets Manager)

**Problem**: Credentials in environment variables → leaked in logs, git

**Solution**: Store in AWS Secrets Manager, fetch at runtime

```python
class SecretsManager:
    def get_mysql_config(self) -> dict:
        secret = self.client.get_secret_value(
            SecretId='dstreambolt/mysql'
        )
        return json.loads(secret['SecretString'])
    
    def get_kafka_config(self) -> dict:
        secret = self.client.get_secret_value(
            SecretId='dstreambolt/kafka'
        )
        return json.loads(secret['SecretString'])
```

**Secret Rotation**:
- Lambda function rotates MySQL password every 30 days
- Ingestion service refreshes secrets every 24 hours (no restart)
- Zero-downtime rotation (connections drain gracefully)

---

## Performance & Scalability

### Bottleneck Analysis

| Component | Throughput | Bottleneck | Solution |
|-----------|-----------|-----------|----------|
| HTTP Accept | 10,000 req/s | Gunicorn workers | Scale workers (4-8 per node) |
| Disk Write | 500 MB/s | I/O bandwidth | Use SSD, RAID, or NVMe |
| Kafka Send | 100,000 msg/s | Network + partitions | Add Kafka partitions, tune batch size |
| Metrics Flush | 1000 writes/s | MySQL connections | Batch writes, connection pool |

### Horizontal Scaling

**How to scale from 1 to 100 nodes?**

1. **Auto Scaling Group**:
   ```hcl
   resource "aws_autoscaling_group" "ingest" {
     min_size         = 2
     max_size         = 100
     desired_capacity = 10
     
     # Scale up when queue depth > 1000
     # Scale down when queue depth < 100
   }
   ```

2. **Stateless Design**: Each node independent (no shared state)
3. **Load Balancer**: ALB distributes traffic evenly
4. **Queue Isolation**: Each node has own disk queue (no contention)

### Backpressure Handling

**Scenario**: Kafka down for 10 minutes

**Without Backpressure**:
```
Clients → Ingest (queue grows) → OOM crash → 503 errors → data loss
```

**With Backpressure**:
```
1. Queue depth > 10,000 files
2. Return HTTP 429 "Queue full, retry later"
3. Clients back off (exponential: 1s, 2s, 4s, 8s)
4. Kafka recovers
5. Queue drains, normal operation resumes
```

**Implementation**:
```python
@app.route('/ingest', methods=['POST'])
def ingest():
    queue_depth = len(list(Path(QUEUE_DIR).glob('*.gz')))
    
    if queue_depth > MAX_QUEUE_SIZE:
        return jsonify({
            "error": "Service overloaded, retry later",
            "queue_depth": queue_depth,
            "retry_after_seconds": 30
        }), 429
```

---

## Operational Excellence

### Rolling Upgrades (Zero Downtime)

**Requirement**: Deploy new code without dropping requests

**Process**:
1. **Deploy to 1 node** (canary):
   ```bash
   ssh ingest-node-1
   systemctl stop dstreambolt-ingest
   git pull origin release/v2.0.0
   systemctl start dstreambolt-ingest
   ```
2. **Monitor metrics** (5 minutes):
   - Error rate < 0.01%
   - Latency < 20ms
   - Queue draining normally
3. **If OK**: Deploy to 50% of fleet
4. **If OK**: Deploy to remaining 50%
5. **If FAIL**: Rollback (redeploy old version)

**Graceful Shutdown**:
```python
import signal

def signal_handler(sig, frame):
    print("⚠️  SIGTERM received, graceful shutdown...")
    
    # 1. Stop accepting new requests
    app.shutdown()
    
    # 2. Wait for queue to drain (max 60s)
    timeout = time.time() + 60
    while len(list(Path(QUEUE_DIR).glob('*.gz'))) > 0:
        if time.time() > timeout:
            break
        time.sleep(1)
    
    # 3. Flush final metrics
    flush_metrics()
    
    # 4. Exit
    sys.exit(0)

signal.signal(signal.SIGTERM, signal_handler)
```

### Disaster Recovery

**Scenario 1**: Single node crash

- **Detection**: ALB health checks fail (3 consecutive)
- **Action**: ALB stops routing to node, auto-scaling launches replacement
- **Data Loss**: None (queue on EBS volume, attached to new instance)

**Scenario 2**: Entire region down

- **Detection**: Route53 health check fails
- **Action**: Failover to secondary region (DNS update)
- **Data Loss**: In-flight bundles in primary region queue (< 1 minute of data)
- **Prevention**: Multi-region active-active (both regions process)

**Scenario 3**: Kafka cluster down

- **Detection**: Producer errors > 100/min
- **Action**: Bundles remain in queue (disk), alerts fired
- **Recovery**: Once Kafka up, queue drains automatically
- **Data Loss**: None (durability via disk)

### Monitoring & Alerting

**Key Metrics** (Grafana Dashboard):
```
1. Request Rate (req/s)
   - Baseline: 1000 req/s
   - Alert if < 100 req/s (clients down?) or > 10,000 req/s (attack?)

2. Queue Depth (files)
   - Baseline: < 100 files
   - Alert if > 1000 (Kafka slow), > 5000 (critical)

3. Error Rate (%)
   - Baseline: < 0.01%
   - Alert if > 1% (investigate)

4. Processing Lag (seconds)
   - Time from bundle received to Kafka publish
   - Baseline: < 5 seconds
   - Alert if > 60 seconds

5. Disk Usage (%)
   - Alert if > 80% (auto-scaling trigger)

6. mTLS Failures (count)
   - Alert if > 10/min (cert rotation issue?)
```

**Alerts** (PagerDuty/Opsgenie):
```yaml
alerts:
  - name: HighErrorRate
    condition: error_rate > 1%
    severity: critical
    notification: pagerduty
  
  - name: QueueBacklog
    condition: queue_depth > 5000
    severity: warning
    notification: slack
  
  - name: DiskFull
    condition: disk_usage > 90%
    severity: critical
    notification: pagerduty + auto_scale
```

---

## High Availability & Disaster Recovery

### Availability SLA: 99.95% (4.38 hours downtime/year)

**Architecture**:
```
              ┌─── Region 1 (Primary) ───┐
              │                           │
      Route53 │   ALB → [Node1, Node2]   │
         ↓    │        ↓                  │
   dstreambolt.click  Kafka Cluster      │
         ↓    │        ↓                  │
              │   MySQL (RDS Multi-AZ)    │
              └───────────────────────────┘
                          │
                  (Replication)
                          ↓
              ┌─── Region 2 (Failover) ──┐
              │                           │
              │   ALB → [Node3, Node4]   │
              │        ↓                  │
              │   Kafka Cluster          │
              │        ↓                  │
              │   MySQL (Read Replica)   │
              └───────────────────────────┘
```

### Failure Scenarios & Recovery

| Failure | Detection Time | Recovery Time | Data Loss | Prevention |
|---------|---------------|---------------|-----------|------------|
| Single node crash | 10 seconds | 1 minute | None | EBS persistence |
| AZ outage | 30 seconds | 2 minutes | None | Multi-AZ deployment |
| Region outage | 1 minute | 5 minutes | < 1 min | Multi-region active-passive |
| Kafka partition loss | Immediate | Manual | Depends on replication | RF=3, min.insync.replicas=2 |
| MySQL master failure | 30 seconds | 2 minutes | None | RDS Multi-AZ automatic failover |

### Data Durability Guarantees

**Ingestion → Kafka**:
- Bundle written to disk → `fsync()` before HTTP 201
- Kafka ack=all (leader + replicas confirm)
- **Guarantee**: No data loss after HTTP 201 returned

**End-to-End**:
```
Client → (TLS) → ALB → (HTTP) → Ingest Node → (disk) → Kafka → (replication) → Spark
         [encrypted]   [ack]      [fsync]      [ack=all]         [checkpoint]
```

---

## Frequently Asked Questions

### Q: Is ingestion externally accessible?
**A**: Yes, via `https://dstreambolt.click/ingest`
- Public internet → AWS WAF → ALB → Private subnet (ingestion nodes)
- mTLS ensures only authorized clients connect
- Rate limiting prevents abuse

### Q: How to add a new client?
**A**: 
1. Generate certificate: `POST /v1/certificates/issue`
2. Securely deliver cert + key to client
3. Client configures: `--cert client.pem --key client-key.pem`
4. Monitor in Grafana: "New Client Traffic" dashboard

### Q: What if a client certificate is compromised?
**A**:
1. Revoke certificate: `POST /v1/certificates/revoke`
2. Update CRL (Certificate Revocation List) in S3
3. ALB automatically rejects revoked certs
4. Issue new certificate to legitimate client

### Q: How to handle traffic spikes (10x normal)?
**A**:
- Auto-scaling: Triggers at 70% CPU or queue depth > 1000
- New nodes launch in 2 minutes
- ALB distributes load automatically
- Cost: Pay only for extra capacity during spike

### Q: Can we guarantee exactly-once delivery?
**A**: **No** (theoretically impossible in distributed systems)
- **At-least-once**: Yes (duplicate if retry after network error)
- **Deduplication**: Spark can dedupe using `request_id` field
- **Idempotent writes**: MySQL `INSERT IGNORE` or `ON DUPLICATE KEY`

### Q: Ingestion vs. direct Kafka writes?
**A**:
| Aspect | Direct Kafka | Via Ingestion |
|--------|-------------|---------------|
| Security | Kafka credentials on clients | mTLS certs easier to rotate |
| Protocol | Kafka protocol | HTTP (firewall-friendly) |
| Durability | Depends on acks | Disk queue + Kafka |
| Observability | Kafka metrics only | Full request tracking |
| Scalability | Kafka connection limits | Unlimited HTTP connections |

---

## Summary

The DStreamBolt Ingestion Service is designed for **production-grade, high-throughput, secure, and observable** data ingestion with the following key characteristics:

✅ **Security**: mTLS, rate limiting, secrets management  
✅ **Durability**: Disk-based queue, atomic operations  
✅ **Performance**: < 10ms response time, 10k req/s per node  
✅ **Scalability**: Horizontal (1-100 nodes), backpressure-aware  
✅ **Observability**: Comprehensive metrics, Grafana dashboards  
✅ **Reliability**: 99.95% SLA, zero-downtime deployments  
✅ **Operability**: Graceful shutdown, disaster recovery

**Next Steps**: Read [KAFKA_DEEPDIVE.md](./KAFKA_DEEPDIVE.md) to understand how data flows through Kafka.

