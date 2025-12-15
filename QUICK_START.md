# DataLens Quick Start Guide

Deploy the Lambda → SQS → Spark → RDS → Grafana pipeline in 20 minutes!

## Prerequisites

✅ **Required:**
- AWS account with admin access
- AWS CLI configured (`aws configure`)
- Terraform 1.0+ installed
- S3 bucket for Akamai logs (or create during deployment)

✅ **Recommended:**
- Domain for Grafana (optional)
- Basic understanding of Terraform
- SSH key pair for EC2 access

---

## Architecture Overview

```
S3 (Akamai logs)
    ↓
Lambda (trigger on .gz upload)
    ↓
SQS (buffer & throttle)
    ↓
Spark Cluster (EC2 t3.medium)
    ↓
RDS PostgreSQL (db.t3.micro)
    ↓
Grafana (on Spark master)
```

**Processing Time**: <3 minutes end-to-end  
**Monthly Cost**: ~$110

---

## Step 1: Prepare AWS Environment

### 1.1 Create S3 Bucket for Akamai Logs

```bash
# Create bucket
export AWS_REGION=us-east-1  # Change to your region
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
aws s3 mb s3://datalens-raw-logs-${ACCOUNT_ID} --region ${AWS_REGION}

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
    --bucket datalens-raw-logs-${ACCOUNT_ID} \
    --versioning-configuration Status=Enabled
```

### 1.2 Configure Akamai DataStream2

In Akamai Control Center:
1. Go to **DataStream 2.0**
2. Create new stream
3. Select destination: **Amazon S3**
4. Configure:
   - **Bucket**: `datalens-raw-logs-{your-account-id}`
   - **Prefix**: `raw/`
   - **Format**: CSV (structured)
   - **Frequency**: Every 1-5 minutes
   - **Compression**: gzip

---

## Step 2: Deploy Infrastructure with Terraform

### 2.1 Clone Repository

```bash
git clone https://github.com/yourusername/datalens.git
cd datalens/terraform-spark-sqs/
```

### 2.2 Configure Variables

Edit `terraform.tfvars`:

```hcl
# Required
aws_region        = "us-east-1"
project_name      = "datalens"
environment       = "prod"

# S3 Configuration
s3_raw_bucket     = "datalens-raw-logs-123456789012"  # Your bucket
s3_raw_prefix     = "raw/"

# Spark Cluster
spark_instance_type    = "t3.medium"   # 2 vCPU, 4 GB RAM
spark_worker_count     = 2             # Master + 1 worker

# Database
db_instance_class      = "db.t3.micro" # 2 vCPU, 1 GB RAM
db_allocated_storage   = 20            # GB

# Optional
grafana_admin_password = "ChangeMe123!"
```

### 2.3 Deploy

```bash
# Initialize Terraform
terraform init

# Review plan
terraform plan

# Deploy (takes ~10 minutes)
terraform apply -auto-approve
```

**What gets created:**
- ✅ Lambda function (S3 event trigger)
- ✅ SQS queue (message buffer)
- ✅ EC2 instances for Spark (master + workers)
- ✅ RDS PostgreSQL database
- ✅ Security groups and IAM roles
- ✅ Grafana on Spark master node

---

## Step 3: Verify Deployment

### 3.1 Get Outputs

```bash
# Get all outputs
terraform output

# Key outputs:
# - spark_master_ip: IP address of Spark master
# - rds_endpoint: Database connection string
# - grafana_url: Grafana dashboard URL
# - sqs_queue_url: SQS queue URL
```

### 3.2 Test Lambda Trigger

```bash
# Upload a test file to S3
echo "test data" | gzip > test.csv.gz
aws s3 cp test.csv.gz s3://datalens-raw-logs-${ACCOUNT_ID}/raw/test.csv.gz

# Check Lambda logs (should see invocation)
aws logs tail /aws/lambda/datalens-s3-trigger --follow

# Check SQS queue (should see message)
aws sqs get-queue-attributes \
    --queue-url $(terraform output -raw sqs_queue_url) \
    --attribute-names ApproximateNumberOfMessages
```

### 3.3 Check Spark Processing

```bash
# SSH to Spark master
SPARK_IP=$(terraform output -raw spark_master_ip)
ssh -i ~/.ssh/your-key.pem ubuntu@${SPARK_IP}

# Check Spark logs
tail -f /opt/spark/logs/spark-processor.log

# Verify Spark job is running
ps aux | grep spark
```

### 3.4 Access Grafana

```bash
# Get Grafana URL
GRAFANA_URL=$(terraform output -raw grafana_url)
echo "Grafana: http://${GRAFANA_URL}:3000"

# Default credentials:
# Username: admin
# Password: (from terraform.tfvars or AWS Secrets Manager)
```

Open in browser: `http://{spark-master-ip}:3000`

---

## Step 4: Configure Grafana Dashboards

### 4.1 Add PostgreSQL Data Source

1. Login to Grafana
2. Go to **Configuration** → **Data Sources** → **Add data source**
3. Select **PostgreSQL**
4. Configure:
   ```
   Host: {rds-endpoint}:5432
   Database: datalens
   User: datalens_user
   Password: (from AWS Secrets Manager)
   SSL Mode: require
   ```
5. Click **Save & Test**

### 4.2 Import Dashboards

```bash
# Import pre-built dashboard
cd ../dashboards/
./import-dashboards.sh
```

Or manually import `customer-analytics-dashboard.json` via Grafana UI.

---

## Step 5: Monitoring & Operations

### 5.1 Check SQS Queue Depth

```bash
# Monitor queue depth
watch -n 5 'aws sqs get-queue-attributes \
    --queue-url $(terraform output -raw sqs_queue_url) \
    --attribute-names ApproximateNumberOfMessages \
    --query "Attributes.ApproximateNumberOfMessages" \
    --output text'
```

**Healthy**: < 100 messages  
**Warning**: 100-1000 messages (may need more Spark workers)  
**Critical**: > 1000 messages (Spark can't keep up)

### 5.2 Check Spark Performance

```bash
# Spark Master UI
open http://${SPARK_IP}:8080

# Check for:
# - Active jobs
# - Worker health
# - Memory usage
```

### 5.3 Check Database Size

```bash
# Connect to RDS
DB_ENDPOINT=$(terraform output -raw rds_endpoint)
psql -h ${DB_ENDPOINT} -U datalens_user -d datalens

# Check table sizes
\dt+
SELECT pg_size_pretty(pg_database_size('datalens'));
```

---

## Troubleshooting

### Lambda Not Triggering

```bash
# Check Lambda function logs
aws logs tail /aws/lambda/datalens-s3-trigger --follow

# Verify S3 event notification
aws s3api get-bucket-notification-configuration \
    --bucket datalens-raw-logs-${ACCOUNT_ID}

# Test Lambda manually
aws lambda invoke \
    --function-name datalens-s3-trigger \
    --payload '{"test": true}' \
    response.json
```

### SQS Messages Not Being Processed

```bash
# Check Spark consumer logs
ssh ubuntu@${SPARK_IP}
tail -f /opt/spark/logs/sqs-consumer.log

# Verify SQS permissions
aws sqs get-queue-attributes \
    --queue-url $(terraform output -raw sqs_queue_url) \
    --attribute-names Policy
```

### Spark Job Failing

```bash
# Check Spark application logs
ssh ubuntu@${SPARK_IP}
cd /opt/spark/logs/
ls -lt  # Find latest log

# Common issues:
# - Out of memory: Increase instance size
# - Can't connect to RDS: Check security groups
# - Can't read from S3: Check IAM role
```

### Database Connection Issues

```bash
# Test database connectivity from Spark master
ssh ubuntu@${SPARK_IP}
psql -h ${DB_ENDPOINT} -U datalens_user -d datalens

# If fails, check:
# 1. Security group allows Spark → RDS (port 5432)
# 2. RDS is publicly accessible (if needed)
# 3. Password is correct (check Secrets Manager)
```

---

## Scaling

### Increase Spark Capacity

Edit `terraform.tfvars`:

```hcl
spark_instance_type = "t3.large"    # 2→4 vCPU, 8 GB RAM
spark_worker_count  = 3             # Add more workers
```

Apply changes:

```bash
terraform apply
```

### Increase Database Size

```hcl
db_instance_class    = "db.t3.small"  # 2 vCPU, 2 GB RAM
db_allocated_storage = 50             # Increase storage
```

### Add Read Replicas

For high query load on Grafana:

```hcl
enable_read_replica = true
read_replica_count  = 1
```

---

## Cost Optimization

### Current Cost (~$110/month)

| Component | Instance | Cost/Month |
|-----------|----------|------------|
| Lambda | Pay-per-use | ~$1 |
| SQS | First 1M free | ~$0 |
| Spark Master | t3.medium | ~$30 |
| Spark Worker | t3.medium | ~$30 |
| RDS | db.t3.micro | ~$15 |
| Data Transfer | ~5 GB | ~$0.50 |
| EBS Storage | 60 GB | ~$6 |
| **Total** | | **~$82** |

### Reduce Costs

1. **Use Spot Instances for Spark** (save 70%):
   ```hcl
   spark_use_spot_instances = true
   ```

2. **Smaller database** (if <100K rows):
   ```hcl
   db_instance_class = "db.t4g.micro"  # ARM, cheaper
   ```

3. **Stop Spark when not processing** (manual):
   ```bash
   aws ec2 stop-instances --instance-ids $(terraform output -raw spark_instance_ids)
   ```

---

## Next Steps

1. **Review Architecture**: Read [`SPARK_SERVERLESS_ARCHITECTURE.md`](./SPARK_SERVERLESS_ARCHITECTURE.md)
2. **Understand Decisions**: Read [`TECHNOLOGY_DECISIONS.md`](./TECHNOLOGY_DECISIONS.md)
3. **Set up Alerts**: Configure CloudWatch alarms
4. **Backup Strategy**: Set up RDS automated backups
5. **Production Hardening**: Review [`OPERATIONS_GUIDE.md`](./OPERATIONS_GUIDE.md)

---

## Support

- **Documentation**: [`DOCUMENTATION_INDEX.md`](./DOCUMENTATION_INDEX.md)
- **Architecture Deep Dive**: [`SPARK_SERVERLESS_ARCHITECTURE.md`](./SPARK_SERVERLESS_ARCHITECTURE.md)
- **Cost Analysis**: [`COST_COMPARISON.md`](./COST_COMPARISON.md)

---

**Deployment Time**: 20 minutes  
**Processing Latency**: <3 minutes  
**Monthly Cost**: ~$110 (optimizable to ~$60)

