# DataLens Quick Start Guide

Get DataLens up and running in 15 minutes!

## Prerequisites

✅ **Required:**
- Kubernetes cluster (EKS, GKE, AKS, or local minikube)
- `kubectl` configured and connected to your cluster
- `helm` 3.x installed
- AWS account with S3 access
- Docker (for building custom Spark image)

✅ **Recommended:**
- 3+ worker nodes (minimum 8 vCPU, 16GB RAM each)
- 200GB+ storage capacity
- AWS CLI configured

## Step 1: Prepare AWS S3

### 1.1 Create S3 Bucket

```bash
# Create bucket for Akamai logs
aws s3 mb s3://datalens-akamai-logs --region us-east-1

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
    --bucket datalens-akamai-logs \
    --versioning-configuration Status=Enabled
```

### 1.2 Configure Akamai DataStream2

In Akamai Control Center:
1. Go to **DataStream 2.0**
2. Create new stream
3. Select destination: **Amazon S3**
4. Configure:
   - Bucket: `datalens-akamai-logs`
   - Prefix: `logs/`
   - Upload frequency: **5 minutes**
   - Compression: **gzip**
   - Format: **Structured** (space-delimited)

### 1.3 Create IAM User for DataLens

```bash
# Create IAM user
aws iam create-user --user-name datalens-s3-reader

# Attach S3 read policy
cat > datalens-s3-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::datalens-akamai-logs",
                "arn:aws:s3:::datalens-akamai-logs/*"
            ]
        }
    ]
}
EOF

aws iam put-user-policy \
    --user-name datalens-s3-reader \
    --policy-name S3ReadOnly \
    --policy-document file://datalens-s3-policy.json

# Create access keys
aws iam create-access-key --user-name datalens-s3-reader
```

**Save the access key ID and secret!**

---

## Step 2: Clone Repository

```bash
git clone https://github.com/yourusername/datalens.git
cd datalens
```

---

## Step 3: Configure Environment

### 3.1 Set AWS Credentials

```bash
export AWS_ACCESS_KEY_ID="AKIAXXXXXXXXXXXXXXXX"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_REGION="us-east-1"
export S3_BUCKET="datalens-akamai-logs"
```

### 3.2 Update Configuration (Optional)

Edit `k8s/configmaps.yaml` if you need to change defaults:

```yaml
data:
  S3_BUCKET: "your-bucket-name"
  S3_REGION: "your-region"
  S3_PREFIX: "logs/"
```

---

## Step 4: Deploy DataLens

### Option A: Automated Deployment (Recommended)

```bash
# Run the all-in-one deployment script
./scripts/deploy-all.sh
```

This will:
- ✅ Create Kubernetes namespace
- ✅ Install Spark Operator
- ✅ Deploy Kafka cluster
- ✅ Deploy TimescaleDB
- ✅ Deploy MinIO
- ✅ Deploy Grafana
- ✅ Create Kafka topics
- ✅ Initialize database schema
- ✅ Build and deploy Spark jobs

**Duration:** ~10-15 minutes

### Option B: Manual Step-by-Step

```bash
# 1. Create namespace
kubectl apply -f k8s/namespace.yaml

# 2. Create secrets
kubectl create secret generic aws-credentials \
    --from-literal=access-key=$AWS_ACCESS_KEY_ID \
    --from-literal=secret-key=$AWS_SECRET_ACCESS_KEY \
    -n datalens

# 3. Apply configmaps
kubectl apply -f k8s/configmaps.yaml

# 4. Install Spark Operator
helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
helm install spark-operator spark-operator/spark-operator \
    --namespace datalens \
    --set webhook.enable=true

# 5. Deploy Kafka
helm repo add bitnami https://charts.bitnami.com/bitnami
helm install kafka bitnami/kafka \
    --namespace datalens \
    --set persistence.size=20Gi \
    --set replicaCount=3

# 6. Deploy TimescaleDB
helm repo add timescale https://charts.timescale.com
helm install timescaledb timescale/timescaledb-single \
    --namespace datalens \
    --set persistentVolumes.data.size=50Gi

# 7. Deploy Grafana
helm repo add grafana https://grafana.github.io/helm-charts
helm install grafana grafana/grafana \
    --namespace datalens \
    --set persistence.enabled=true

# 8. Build Spark image
docker build -t datalens/spark-py:3.5.0 -f Dockerfile.spark .

# 9. Deploy Spark job
kubectl apply -f k8s/spark/spark-s3-processor.yaml
```

---

## Step 5: Verify Deployment

### 5.1 Check Pod Status

```bash
kubectl get pods -n datalens
```

Expected output:
```
NAME                                READY   STATUS    RESTARTS   AGE
kafka-0                             1/1     Running   0          5m
kafka-1                             1/1     Running   0          5m
kafka-2                             1/1     Running   0          5m
timescaledb-0                       1/1     Running   0          5m
grafana-xxxx-yyyy                   1/1     Running   0          5m
spark-operator-xxxx-yyyy            1/1     Running   0          5m
```

### 5.2 Check Spark Application

```bash
kubectl get sparkapplications -n datalens
```

Expected:
```
NAME                    STATUS      AGE
akamai-s3-processor     RUNNING     2m
```

### 5.3 View Logs

```bash
# Spark driver logs
kubectl logs -f -l app=datalens-spark-driver -n datalens

# Kafka logs
kubectl logs kafka-0 -n datalens

# TimescaleDB logs
kubectl logs timescaledb-0 -n datalens
```

---

## Step 6: Access Dashboards

### 6.1 Get Grafana Password

```bash
kubectl get secret grafana-credentials -n datalens \
    -o jsonpath='{.data.admin-password}' | base64 -d
echo
```

### 6.2 Port Forward Grafana

```bash
kubectl port-forward svc/grafana 3000:80 -n datalens
```

Open browser: **http://localhost:3000**

Login:
- Username: `admin`
- Password: (from step 6.1)

### 6.3 Access Spark UI

```bash
kubectl port-forward svc/akamai-s3-processor-ui 4040:4040 -n datalens
```

Open browser: **http://localhost:4040**

---

## Step 7: Test with Sample Data

### 7.1 Upload Sample Akamai Log

Create a sample log file:

```bash
cat > sample-akamai.log <<'EOF'
1 123456 req001 1702512000 12345 1 2 2 602093 4995 203.0.113.45 200 HTTPS cdn.example.com GET /video/stream.m3u8 443 5000 application/vnd.apple.mpegurl Mozilla/5.0+(iPhone) 0 TLSv1.3 484 484 232 quality=high 5000 1MB-10MB 1 1 1 0 en-US session123 bytes=0-1000 https://example.com/player 192.0.2.100 3600 100 50 200 - 15 1 15001 2500 500 0 1 //BC/xyz 1 US SanFrancisco California 203.0.113.45 US 1 - - - - 1 1 0 - custom123
EOF

# Compress
gzip sample-akamai.log

# Upload to S3
aws s3 cp sample-akamai.log.gz \
    s3://datalens-akamai-logs/logs/2025/12/13/00/
```

### 7.2 Trigger Processing

```bash
# The Spark job will automatically detect and process new files
# Or manually trigger:
kubectl delete sparkapplication akamai-s3-processor -n datalens
kubectl apply -f k8s/spark/spark-s3-processor.yaml
```

### 7.3 Verify Data in TimescaleDB

```bash
# Connect to TimescaleDB
kubectl exec -it timescaledb-0 -n datalens -- psql -U postgres -d datalens_metrics

# Query data
SELECT COUNT(*) FROM akamai_logs;
SELECT country, COUNT(*) FROM akamai_logs GROUP BY country;
```

---

## Step 8: Configure Grafana Dashboards

### 8.1 Add TimescaleDB Data Source

In Grafana:
1. Go to **Configuration** → **Data Sources**
2. Click **Add data source**
3. Select **PostgreSQL**
4. Configure:
   - Host: `timescaledb.datalens.svc.cluster.local:5432`
   - Database: `datalens_metrics`
   - User: `postgres`
   - Password: (from secrets)
   - SSL Mode: `require`
   - Version: 12+
   - TimescaleDB: **enabled**
5. Click **Save & Test**

### 8.2 Import Pre-built Dashboard

```bash
# Import dashboard JSON
kubectl exec -it grafana-xxxx-yyyy -n datalens -- sh
cd /var/lib/grafana/dashboards
# Copy dashboard JSONs from repository
```

Or use Grafana UI:
1. **Dashboards** → **Import**
2. Upload `dashboards/performance.json`
3. Select TimescaleDB data source
4. Click **Import**

### 8.3 Create Custom Dashboard

Example query for request rate:

```sql
SELECT 
    time_bucket('5 minutes', request_timestamp) AS time,
    COUNT(*) as requests_per_5min
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY time
ORDER BY time;
```

---

## Step 9: Production Checklist

Before going to production:

- [ ] **Security**
  - [ ] Enable network policies
  - [ ] Rotate all default passwords
  - [ ] Configure TLS for all services
  - [ ] Set up RBAC properly

- [ ] **Monitoring**
  - [ ] Deploy Prometheus for metrics
  - [ ] Set up alerts for job failures
  - [ ] Configure log aggregation (ELK/Loki)

- [ ] **Backup**
  - [ ] Configure TimescaleDB backups to S3
  - [ ] Export Grafana dashboards to Git
  - [ ] Document recovery procedures

- [ ] **Performance**
  - [ ] Tune Spark executor count based on data volume
  - [ ] Set up auto-scaling policies
  - [ ] Configure resource quotas

- [ ] **Cost**
  - [ ] Review S3 lifecycle policies
  - [ ] Use spot instances for Spark (if on AWS)
  - [ ] Set up cost alerts

---

## Troubleshooting

### Issue: Spark job not starting

```bash
# Check Spark operator logs
kubectl logs -l app.kubernetes.io/name=spark-operator -n datalens

# Check driver pod
kubectl describe pod -l app=datalens-spark-driver -n datalens

# Common fix: Resource constraints
kubectl get resourcequota -n datalens
```

### Issue: Cannot connect to S3

```bash
# Verify credentials
kubectl get secret aws-credentials -n datalens -o yaml

# Test S3 access from pod
kubectl run -it --rm debug --image=amazon/aws-cli --restart=Never -n datalens -- \
    s3 ls s3://datalens-akamai-logs/
```

### Issue: TimescaleDB connection failed

```bash
# Check TimescaleDB status
kubectl logs timescaledb-0 -n datalens

# Test connection
kubectl exec -it timescaledb-0 -n datalens -- \
    psql -U postgres -d datalens_metrics -c "SELECT version();"
```

### Issue: Kafka consumer lag

```bash
# Check Kafka topics
kubectl exec kafka-0 -n datalens -- kafka-topics.sh --list --bootstrap-server localhost:9092

# Check consumer group lag
kubectl exec kafka-0 -n datalens -- kafka-consumer-groups.sh \
    --bootstrap-server localhost:9092 \
    --describe --group datalens-processors
```

---

## Next Steps

1. **Explore the Architecture**: Read [ARCHITECTURE.md](ARCHITECTURE.md) for deep dive
2. **Use Cases**: Check [USE_CASES.md](USE_CASES.md) for analytics examples
3. **Operations Guide**: See [OPERATIONS_GUIDE.md](OPERATIONS_GUIDE.md) for day-2 operations
4. **Customize**: Modify Spark jobs in `spark-jobs/` for your needs

---

## Getting Help

- 📖 **Documentation**: [docs/](docs/)
- 🐛 **Issues**: https://github.com/yourusername/datalens/issues
- 💬 **Discussions**: https://github.com/yourusername/datalens/discussions
- 📧 **Email**: support@datalens.io

---

**Congratulations! DataLens is now running** 🎉

You're ready to process Akamai CDN logs at scale!

