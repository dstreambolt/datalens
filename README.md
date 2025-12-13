# DStreamBolt Platform

Production-ready, cost-effective infrastructure for real-time data ingestion, processing, and monitoring built on AWS.

## 📚 Documentation

**Complete Documentation Suite:** 415 pages | 9 comprehensive guides | 100% production-ready

### 📖 Start Here
- **[DOCUMENTATION_INDEX.md](./docs/DOCUMENTATION_INDEX.md)** - Complete documentation catalog and navigation guide
- **[README.md](./README.md)** - This file - Quick start and overview

### 🏗️ Architecture & Design
- **[ARCHITECTURE.md](./ARCHITECTURE.md)** - System architecture, design decisions, data flow diagrams (50 pages)

### 🔧 Technical Implementation
- **[COMPLETE_TECHNICAL_GUIDE.md](./docs/COMPLETE_TECHNICAL_GUIDE.md)** - Comprehensive technical guide (45 pages)
- **[INGESTION_DEEPDIVE.md](./docs/INGESTION_DEEPDIVE.md)** - Ingestion layer deep dive (24 pages)
- **[KAFKA_DEEPDIVE.md](./docs/KAFKA_DEEPDIVE.md)** - Kafka operations and best practices (23 pages)
- **[SPARK_DEEPDIVE.md](./docs/SPARK_DEEPDIVE.md)** - Spark processing and optimization (27 pages)
- **[SCHEMA_EVOLUTION_AND_FAILURES.md](./docs/SCHEMA_EVOLUTION_AND_FAILURES.md)** - Schema changes & failure scenarios (54 pages)

### 💼 Business & Value
- **[BUSINESS_USE_CASES.md](./docs/BUSINESS_USE_CASES.md)** - 10 use cases, ROI analysis, industry applications (80 pages)

### ⚙️ Operations
- **[OPERATIONS_GUIDE.md](./OPERATIONS_GUIDE.md)** - Complete operational procedures and runbooks (55 pages)

### 🎯 Quick References
- **[QUICK_REFERENCE.md](./QUICK_REFERENCE.md)** - Command cheat sheet
- **[SETUP_GUIDE.md](./setup_scripts/README.md)** - Installation guide

---

## 🚀 Quick Start

```bash
# 1. Clone repository
git clone https://github.com/dstreambolt/dstream_cloud.git
cd dstream_cloud

# 2. Deploy infrastructure
cd terraform
./deploy.sh

# 3. Setup all services
cd ../setup_scripts
./setup_all.sh

# 4. Test the pipeline
cd ../examples
python3 02-send-to-ingest.py --alb-url <your-alb-url> --file logs/access.log

# 5. View results
open http://<devops-ip>:3000/grafana  # Grafana dashboards
```

**Total Setup Time:** ~45 minutes

---

## 🏗️ High-Level Architecture

```
External Clients (mTLS)
         │
         ▼
┌─────────────────┐
│ Application     │  HTTPS/443
│ Load Balancer   │
└────────┬────────┘
         │
    ┌────┴────┬──────────┬──────────┐
    ▼         ▼          ▼          ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│Ingest  │ │DevOps  │ │ Spark  │ │Grafana │
│Service │ │Jenkins │ │Cluster │ │MySQL   │
└───┬────┘ └────────┘ └────┬───┘ └────────┘
    │                      │
    └──────► Kafka ◄───────┘
         (Message Queue)
```

**See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed architecture diagrams and explanations.**

---

## 📁 Repository Structure

```
dstream_bolt/
├── ingestion/          # Ingestion service (Flask app)
│   ├── app.py          # Main ingestion application
│   ├── requirements.txt
│   └── README.md       # Ingestion service documentation
│
├── computations/       # Spark processing jobs
│   ├── spark_processor.py  # Batch and streaming processor
│   ├── requirements.txt
│   └── README.md       # Spark jobs documentation
│
├── terraform/          # Infrastructure as Code
│   ├── main.tf         # Root Terraform configuration
│   ├── terraform.tfvars # Variables configuration
│   ├── deploy.sh       # Automated deployment script
│   ├── modules/        # Terraform modules
│   │   ├── networking/ # VPC, subnets, security groups
│   │   ├── ingest/     # Ingestion instance
│   │   ├── kafka/      # Kafka broker instance
│   │   ├── compute/    # Spark cluster instance
│   │   ├── devops/     # DevOps tools instance
│   │   └── alb/        # Application Load Balancer
│   └── user_data/      # EC2 initialization scripts
│
├── jenkins/            # Jenkins CI/CD pipelines
│   ├── deploy-ingestion.jenkinsfile  # Ingestion deployment pipeline
│   ├── deploy-spark-jobs.jenkinsfile # Spark jobs deployment pipeline
│   ├── setup_jenkins_jobs.sh         # Quick setup script
│   └── README.md       # Jenkins jobs documentation
│
├── setup_scripts/      # ⭐ Production setup scripts (NEW)
│   ├── setup_all.sh           # Master orchestrator script
│   ├── setup_jenkins.sh       # Jenkins CI/CD setup
│   ├── setup_grafana.sh       # Grafana monitoring setup
│   ├── setup_mysql.sh         # MySQL database with schema
│   ├── setup_kafka.sh         # Kafka + Zookeeper
│   ├── setup_spark_master.sh  # Spark Master + Worker
│   ├── setup_spark_worker.sh  # Spark Executor
│   ├── setup_ingestion.sh     # Ingestion API service
│   ├── setup_akhq.sh          # AKHQ Kafka UI
│   └── README.md              # Complete setup guide
│
├── examples/           # Example scripts and dashboards
│   ├── 01-generate-logs.py      # Generate sample logs
│   ├── 02-send-to-ingest.py     # Send logs to ingestion
│   ├── 03-kafka-consumer.py     # Consume from Kafka
│   ├── 04-spark-processor.py    # Spark job example
│   ├── grafana-dashboard.json   # Pre-configured dashboard
│   ├── requirements.txt
│   └── README.md       # Examples documentation
│
├── utils/              # Utility scripts
│   └── login.sh        # ⭐ Smart SSH helper (enhanced)
│
├── SETUP_COMPLETE_GUIDE.md      # ⭐ Complete setup walkthrough
├── INFRASTRUCTURE_STATUS.md     # ⭐ 15-point checklist
└── README.md           # This file
```

## 🆕 Quick Setup (NEW!)

**One-command setup for all infrastructure components:**

```bash
# 1. SSH to target node
./utils/login.sh devops

# 2. Copy setup scripts
scp -i ~/dstreambolt-access-key.pem -r setup_scripts ubuntu@<ip>:/tmp/

# 3. Run setup
sudo /tmp/setup_scripts/setup_all.sh
```

**See comprehensive guides:**
- [SETUP_COMPLETE_GUIDE.md](SETUP_COMPLETE_GUIDE.md) - Complete setup walkthrough
- [INFRASTRUCTURE_STATUS.md](INFRASTRUCTURE_STATUS.md) - 15-point verification checklist
- [setup_scripts/README.md](setup_scripts/README.md) - Detailed script documentation

## 🏗️ Architecture Overview

```
┌─────────────────┐
│   Internet      │
└────────┬────────┘
         │
    ┌────▼─────┐
    │   ALB    │ (mTLS + HTTPS)
    │  Landing │
    └────┬─────┘
         │
         ├──────────────────┬─────────────────┬──────────────────┐
         │                  │                 │                  │
    ┌────▼─────┐      ┌────▼────┐      ┌────▼────┐      ┌─────▼─────┐
    │ Ingest   │      │ DevOps  │      │  Kafka  │      │  Spark    │
    │ (Public) │      │(Public) │      │(Private)│      │ (Private) │
    └──────────┘      └─────────┘      └─────────┘      └───────────┘
    • mTLS            • Jenkins         • Broker         • Master
    • Gzip handler    • AKHQ            • ZooKeeper      • Worker
    • MySQL metrics   • Grafana                          • History
    • Kafka produce   • MySQL
```

## 🎯 Infrastructure Components

### 1. **dstreambolt-ingest** (Ingestion Instance)
- **Purpose**: Accept gzipped POST requests via mTLS-enabled ALB
- **Instance**: t3.micro (public subnet)
- **Port**: 5000 (behind ALB)
- **Functions**:
  - Accepts POST with gzipped bundles (up to 10 MB)
  - Returns `201 Accepted` immediately
  - Writes metrics to MySQL (requests, bundle_status, failures)
  - Unzips bundles and writes logs to Kafka
  - Health endpoint: `/health`

### 2. **dstreambolt-kafka** (Kafka Instance)
- **Purpose**: Message broker for log streaming
- **Instance**: t3.micro (private subnet)
- **Access**: Only from ingest and devops instances
- **Components**: Kafka broker + ZooKeeper
- **Port**: 9092 (internal only)

### 3. **dstreambolt-compute** (Spark Instance)
- **Purpose**: Data processing and analytics
- **Instance**: t3.micro (private subnet)
- **Components**: Spark Master + Worker (same node)
- **Access**: From DevOps (Jenkins, Grafana)
- **Ports**: 7077 (master), 8080 (UI)

### 4. **dstreambolt-devops** (DevOps Instance)
- **Purpose**: CI/CD, monitoring, and management
- **Instance**: t3.small (public subnet)
- **Services**:
  - Jenkins CI/CD (port 8081)
  - AKHQ Kafka UI (port 8080)
  - Grafana Monitoring (port 3000)
  - MySQL Database (port 3306)
- **Access**: All other instances

## 🚀 Quick Start

### Prerequisites

1. **AWS Account** with appropriate permissions
2. **AWS CLI** configured with credentials
3. **Terraform** v1.13.5 or later
4. **Python 3.8+** for running examples and applications
5. **SSH Key**: Create or use existing key at `~/dstreambolt-access-key.pem`

### Deploy Infrastructure

```bash
# 1. Clone or navigate to repository
cd /path/to/dstream_bolt

# 2. Navigate to terraform directory
cd terraform

# 3. Initialize Terraform
terraform init

# 4. Review and customize terraform.tfvars
# Edit: project_name, aws_region, mysql_root_password, etc.

# 5. Plan deployment
terraform plan -out=tfplan

# 6. Deploy (takes ~15-20 minutes)
terraform apply tfplan
```

**Or use automated script:**
```bash
cd terraform
./deploy.sh
```

### Post-Deployment

After deployment completes:
1. Get ALB URL: `terraform output alb_url`
2. Access landing page: `https://<alb-dns>/`
3. Note down service IPs from outputs

## 📡 Sending Data to DStreamBolt

### Ingestion Endpoint

**URL**: `https://<ALB-DNS>/ingest`

The ingestion service accepts POST requests with gzipped log bundles.

### Example: Send Data

#### 1. Prepare Your Data
```bash
# Create a log file
cat > logs.txt << EOF
2025-12-07 10:00:01 INFO Application started
2025-12-07 10:00:02 DEBUG Connection established
2025-12-07 10:00:03 INFO Processing batch 1
EOF

# Gzip the file
gzip logs.txt  # Creates logs.txt.gz
```

#### 2. Send via cURL (with mTLS)
```bash
# Get ALB URL
ALB_URL=$(terraform output -raw alb_url)

# Send gzipped bundle
curl -X POST \
  --cert client-cert.pem \
  --key client-key.pem \
  --cacert ca-cert.pem \
  -H "Content-Type: application/gzip" \
  -H "Content-Encoding: gzip" \
  --data-binary @logs.txt.gz \
  "$ALB_URL/ingest"

# Expected Response: HTTP 201 Accepted
```

#### 3. Send via Python
```python
import requests
import gzip
import io

# Prepare data
log_data = """
2025-12-07 10:00:01 INFO Application started
2025-12-07 10:00:02 DEBUG Connection established
"""

# Gzip the data
buffer = io.BytesIO()
with gzip.GzipFile(fileobj=buffer, mode='wb') as gz:
    gz.write(log_data.encode('utf-8'))
gzipped_data = buffer.getvalue()

# Send to ingestion endpoint
response = requests.post(
    'https://<ALB-DNS>/ingest',
    data=gzipped_data,
    headers={
        'Content-Type': 'application/gzip',
        'Content-Encoding': 'gzip'
    },
    cert=('client-cert.pem', 'client-key.pem'),
    verify='ca-cert.pem'
)

print(f"Status: {response.status_code}")  # Should be 201
```

### Health Check
```bash
curl https://<ALB-DNS>/health

# Response:
# {
#   "status": "healthy",
#   "kafka": "connected",
#   "mysql": "connected",
#   "timestamp": 1234567890
# }
```

## 🌐 Service Access

### ALB Landing Page

**URL**: `https://<ALB-DNS>/`

Beautiful dashboard with links to all services:
- Ingestion API documentation
- Jenkins CI/CD
- Grafana dashboards
- Kafka Manager (AKHQ)
- Spark UI

### Direct Access to Services

| Service | URL | Port | Credentials |
|---------|-----|------|-------------|
| **Landing Page** | https://\<ALB-DNS>/ | 443 | N/A |
| **Ingest API** | https://\<ALB-DNS>/ingest | 443 | mTLS cert required |
| **Jenkins** | http://\<DevOps-IP>:8081 | 8081 | See `/var/lib/jenkins/secrets/initialAdminPassword` |
| **AKHQ** | http://\<DevOps-IP>:8080 | 8080 | No login required |
| **Grafana** | http://\<DevOps-IP>:3000 | 3000 | admin / DStreamBolt2025! |
| **MySQL** | mysql://\<DevOps-IP>:3306 | 3306 | root / DStreamBolt2025! (VPC only) |

### Get Service URLs
```bash
# Get all URLs
terraform output

# Specific outputs
terraform output alb_url           # ALB URL
terraform output ingestion_api_url # Ingestion endpoint
terraform output direct_access     # Direct IP access
```

## ⚠️ Important: Firewall Configuration

### Instance Firewall (UFW)

The DevOps instance UFW must allow these ports:
```bash
sudo ufw allow 22/tcp     # SSH
sudo ufw allow 80/tcp     # HTTP (landing page)
sudo ufw allow 3000/tcp   # Grafana
sudo ufw allow 8080/tcp   # AKHQ
sudo ufw allow 8081/tcp   # Jenkins
```

### AWS Security Group

The security group must allow inbound access to:
- Port 22 (SSH) - from anywhere
- Port 80 (HTTP) - from anywhere
- Port 3000 (Grafana) - from anywhere
- Port 8080 (AKHQ) - from anywhere
- Port 8081 (Jenkins) - from anywhere

**If services are not accessible**, add missing ports:
```bash
aws ec2 authorize-security-group-ingress \
  --region ap-south-1 \
  --group-id <security-group-id> \
  --protocol tcp \
  --port 8081 \
  --cidr 0.0.0.0/0
```

## 📁 Repository Structure

```
dstream_bolt/
├── README.md                   # Complete guide (this file)
├── main.tf                     # Main Terraform configuration
├── variables.tf                # Variable definitions
├── outputs.tf                  # Output values
├── terraform.tfvars            # Variable values (DO NOT COMMIT)
│
├── modules/                    # Terraform modules (dedicated per role)
│   ├── networking/            # VPC, subnets, routing, security groups
│   ├── alb/                   # Application Load Balancer + landing page
│   ├── ingest/                # Ingestion instance + Flask service
│   ├── kafka/                 # Kafka broker (private subnet)
│   ├── compute/               # Spark master + worker
│   └── devops/                # Jenkins, AKHQ, Grafana, MySQL
│
├── user_data/                  # Instance initialization scripts
│   ├── ingest.sh              # Ingestion service setup (Flask + Kafka producer)
│   ├── kafka.sh               # Kafka + ZooKeeper setup
│   ├── compute.sh             # Spark master + worker setup
│   └── devops.sh              # Jenkins, AKHQ, Grafana, MySQL setup
│
├── certs/                      # SSL/TLS certificates for mTLS
│   ├── ca-cert.pem            # Certificate Authority
│   ├── server-cert.pem        # Server certificate
│   ├── server-key.pem         # Server private key
│   ├── client-cert.pem        # Client certificate
│   └── client-key.pem         # Client private key
│
├── deploy.sh                   # Automated deployment script
└── update_devops_services.sh   # Manual service update script
```

### Module Organization

Each module is self-contained with:
- `main.tf` - Resource definitions
- `variables.tf` - Input variables
- `outputs.tf` - Output values
- `README.md` - Module documentation (optional)

## 🔧 Configuration

### Key Variables (terraform.tfvars)

```hcl
project_name = "dstreambolt"
aws_region   = "ap-south-1"
key_name     = "dstreambolt-access-key"

# Instance types
devops_instance_type = "t3.small"   # Jenkins, Grafana, AKHQ, MySQL
kafka_instance_type  = "t3.micro"   # Kafka broker
spark_instance_type  = "t3.micro"   # Spark master + worker
ingest_instance_type = "t3.micro"   # Ingestion API

# MySQL password
mysql_root_password = "DStreamBolt2025!"
```

### Service Ports

| Service | Port | Access |
|---------|------|--------|
| Jenkins | 8081 | Public |
| AKHQ | 8080 | Public |
| Grafana | 3000 | Public |
| MySQL | 3306 | VPC only |
| Kafka | 9092 | VPC only |
| Spark Master | 7077 | VPC only |
| Spark UI | 8080 | VPC only |

## 📊 Data Flow

### Complete Pipeline

```
Client App
    │ (POST gzipped logs)
    ↓
ALB (mTLS validation)
    │
    ↓
Ingest Service (Flask/Python)
    │
    ├──→ MySQL (Metrics: request count, status, failures)
    │
    └──→ Kafka (Raw log data)
           │
           ↓
       Spark Cluster (Processing)
           │
           ↓
       Storage/Analytics
```

### What Happens When You Send Data

1. **POST Request** → ALB validates mTLS certificate
2. **ALB** → Forwards to Ingestion service
3. **Ingest Service**:
   - Returns `201 Accepted` immediately
   - Logs request to MySQL (timestamp, size, client)
   - Unzips bundle in background
   - Writes log lines to Kafka topic
4. **Kafka** → Stores logs for stream processing
5. **Spark** → Consumes from Kafka, processes, stores
6. **Grafana** → Visualizes metrics from MySQL

## 🗂️ Data Schema

### MySQL Metrics Table

```sql
CREATE TABLE ingestion_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    bundle_size INT,
    bundle_status VARCHAR(50),  -- 'accepted', 'processing', 'failed'
    client_ip VARCHAR(45),
    processing_time_ms INT,
    kafka_status VARCHAR(50),
    error_message TEXT
);
```

### Kafka Topic

- **Topic Name**: `dstreambolt-logs`
- **Partitions**: 1
- **Replication**: 1 (single broker)
- **Message Format**: Plain text log lines

## 🛠️ Maintenance

### Check Service Status

```bash
# SSH to DevOps node
ssh -i ~/dstreambolt-access-key.pem ubuntu@<devops-ip>

# Check all services
sudo systemctl status jenkins akhq grafana-server mysql

# View logs
sudo journalctl -u jenkins -n 50 --no-pager
sudo journalctl -u akhq -n 50 --no-pager
```

### Restart Services

```bash
sudo systemctl restart jenkins
sudo systemctl restart akhq
sudo systemctl restart grafana-server
```

### Update Services on Existing Instance

```bash
# Copy update script to instance
scp -i ~/dstreambolt-access-key.pem update_devops_services.sh ubuntu@<devops-ip>:/tmp/

# Run update script
ssh -i ~/dstreambolt-access-key.pem ubuntu@<devops-ip>
sudo bash /tmp/update_devops_services.sh
```

## 🔒 Security Features

- ✅ All secrets stored in AWS Secrets Manager
- ✅ mTLS enabled for ingestion service
- ✅ Security groups restrict access by port and source
- ✅ Private subnets for Kafka and backend services
- ✅ IAM roles with least privilege access
- ✅ VPC flow logs for network monitoring

## 💰 Cost Optimization

Current infrastructure uses minimal resources:

| Resource | Type | Monthly Cost |
|----------|------|--------------|
| DevOps Instance | t3.small | ~$15 |
| Kafka Instance | t3.micro | ~$7 |
| Spark Instance | t3.micro | ~$7 |
| Ingest Instance | t3.micro | ~$7 |
| ALB | Application | ~$20 |
| **Total** | | **~$56/month** |

## 🚨 Troubleshooting

### Services Not Accessible from Browser

**Symptom**: ERR_CONNECTION_TIMED_OUT when accessing http://IP:8081

**Solution**:
1. Check UFW firewall on instance:
   ```bash
   ssh -i ~/dstreambolt-access-key.pem ubuntu@<ip>
   sudo ufw status | grep 8081
   # If not listed:
   sudo ufw allow 8081/tcp
   ```

2. Check AWS Security Group:
   ```bash
   aws ec2 describe-security-groups --region ap-south-1 --group-ids <sg-id>
   # Add rule if missing:
   aws ec2 authorize-security-group-ingress --region ap-south-1 \
     --group-id <sg-id> --protocol tcp --port 8081 --cidr 0.0.0.0/0
   ```

3. Verify service is listening:
   ```bash
   sudo ss -tlnp | grep 8081
   ```

### Jenkins Not Starting

**Symptom**: Jenkins service fails to start

**Solution**:
```bash
# Check Java version (needs Java 17)
java -version

# View error logs
sudo journalctl -u jenkins -n 100 --no-pager

# Check Jenkins is configured for port 8081
cat /etc/systemd/system/jenkins.service.d/override.conf
```

### AKHQ Not Connecting to Kafka

**Symptom**: AKHQ shows "No clusters available"

**Solution**:
```bash
# Check Kafka is running
ssh -i ~/dstreambolt-access-key.pem ubuntu@<kafka-ip>
sudo systemctl status kafka

# Verify AKHQ configuration
cat /opt/akhq/config/application.yml
# Should show: bootstrap.servers: "10.0.10.101:9092"

# Restart AKHQ
sudo systemctl restart akhq
```

### Landing Page Shows Wrong IP

**Symptom**: Links on landing page point to wrong IP

**Solution**: The page is generated during instance launch. Recreate it:
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@<devops-ip>
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
sudo sed -i "s/PUBLIC_IP/$PUBLIC_IP/g" /var/www/html/index.html
```

## 🔄 Updates

### Recent Changes (December 2025)

- ✅ Updated Jenkins to port 8081 (was 8080)
- ✅ Replaced Kafka Manager (CMAK) with AKHQ on port 8080
- ✅ Added Java 17 for latest Jenkins
- ✅ Created professional landing page with hyperlinks
- ✅ Fixed UFW firewall rules
- ✅ Updated all documentation

## 📞 Support

For issues:
1. Check documentation in this repository
2. Review Terraform plan output
3. Check AWS Console for resource status
4. Review service logs on instances

## 📂 Directory Documentation

### 1. `ingestion/` - Ingestion Service

Flask-based lightweight service for receiving gzipped log bundles.

**Key Files:**
- `app.py` - Main application with Flask endpoints
- `requirements.txt` - Python dependencies
- `README.md` - Detailed ingestion service documentation

**Features:**
- POST endpoint for gzipped bundles
- MySQL metrics tracking
- Kafka producer integration
- Health check endpoint

**Quick Start:**
```bash
cd ingestion
pip install -r requirements.txt
python app.py
```

See [ingestion/README.md](ingestion/README.md) for full documentation.

### 2. `computations/` - Spark Processing

Apache Spark jobs for batch and real-time processing.

**Key Files:**
- `spark_processor.py` - Main Spark application
- `requirements.txt` - Python dependencies
- `README.md` - Spark jobs documentation

**Features:**
- Batch processing from Kafka
- Real-time streaming with windowed aggregations
- MySQL output support
- Error detection and analysis

**Quick Start:**
```bash
cd computations
pip install -r requirements.txt

# Run batch processing
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode batch

# Run streaming
python spark_processor.py \
  --spark-master spark://10.0.11.80:7077 \
  --kafka-broker 10.0.10.101:9092 \
  --mode streaming
```

See [computations/README.md](computations/README.md) for full documentation.

### 3. `terraform/` - Infrastructure as Code

Complete AWS infrastructure definition using Terraform.

**Key Files:**
- `main.tf` - Root configuration
- `terraform.tfvars` - Variable values
- `deploy.sh` - Automated deployment script
- `modules/` - Reusable infrastructure modules
- `user_data/` - EC2 initialization scripts

**Modules:**
- `networking/` - VPC, subnets, security groups, NAT
- `ingest/` - Ingestion EC2 instance
- `kafka/` - Kafka broker instance
- `compute/` - Spark master + worker
- `devops/` - Jenkins, AKHQ, Grafana, MySQL
- `alb/` - Application Load Balancer with mTLS

**Quick Start:**
```bash
cd terraform
terraform init
terraform plan
terraform apply
```

See [terraform/README.md](terraform/README.md) for module documentation.

### 4. `jenkins/` - CI/CD Pipelines

Jenkins pipeline scripts for automated deployments.

**Key Files:**
- `deploy-ingestion.jenkinsfile` - Ingestion service deployment
- `deploy-spark-jobs.jenkinsfile` - Spark jobs deployment
- `setup_jenkins_jobs.sh` - Quick setup script
- `README.md` - Complete Jenkins documentation

**Features:**
- Deploy to single or multiple servers
- Parallel deployment support
- Graceful shutdown of existing jobs
- Automatic health checks
- Backup and rollback support

**Quick Start:**
```bash
cd jenkins
./setup_jenkins_jobs.sh

# Or manually create jobs in Jenkins:
# 1. New Item → Pipeline
# 2. SCM: Git → https://github.com/dstreambolt/dstream_cloud.git
# 3. Script Path: jenkins/deploy-ingestion.jenkinsfile
```

**Deploy Ingestion:**
```
Job: DStreamBolt-Deploy-Ingestion
Parameters:
  - TARGET_IPS: 13.201.43.125,52.66.123.45
  - GIT_BRANCH: main
  - RESTART_SERVICE: ✓
```

**Deploy Spark:**
```
Job: DStreamBolt-Deploy-Spark
Parameters:
  - SPARK_MASTER_IPS: 43.205.94.74
  - KAFKA_BROKER: 10.0.10.101:9092
  - PROCESSING_MODE: streaming
  - AUTO_START: ✓
```

See [jenkins/README.md](jenkins/README.md) for detailed documentation.

### 5. `examples/` - Example Scripts

Working examples for using the platform.

**Scripts:**
- `01-generate-logs.py` - Generate realistic access logs
- `02-send-to-ingest.py` - Send data to ingestion service
- `03-kafka-consumer.py` - Consume from Kafka topics
- `04-spark-processor.py` - Spark processing example
- `grafana-dashboard.json` - Pre-configured dashboard

**Quick Start:**
```bash
cd examples
pip install -r requirements.txt

# Generate logs
python 01-generate-logs.py --count 1000

# Send to ingestion
python 02-send-to-ingest.py \
  --alb-url https://your-alb.amazonaws.com \
  --file logs/access.log
```

See [examples/README.md](examples/README.md) for detailed usage.

## 🔄 Development Workflow

### 1. Local Development

**Ingestion Service:**
```bash
cd ingestion
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Set environment variables
export MYSQL_HOST=localhost
export KAFKA_BROKER=localhost:9092
export DEBUG=true

# Run locally
python app.py
```

**Spark Jobs:**
```bash
cd computations
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run with local Spark
python spark_processor.py \
  --spark-master local[2] \
  --kafka-broker localhost:9092 \
  --mode batch
```

### 2. Testing Changes

**Test Ingestion:**
```bash
# Generate test data
cd examples
python 01-generate-logs.py --count 100 --output test.log

# Send to local ingestion
python 02-send-to-ingest.py \
  --alb-url http://localhost:5000 \
  --file test.log \
  --no-verify
```

**Test Spark:**
```bash
# Consume from Kafka
python 03-kafka-consumer.py \
  --broker localhost:9092 \
  --max-messages 10
```

### 3. Deploy to AWS

**Update Infrastructure:**
```bash
cd terraform
terraform plan
terraform apply
```

**Deploy Code Changes:**
```bash
# Ingestion service is deployed via user_data
# To update: modify user_data/ingest.sh, then:
terraform taint module.ingest.aws_instance.ingest
terraform apply

# Or SSH and update manually:
ssh -i ~/dstreambolt-access-key.pem ubuntu@<ingest-ip>
cd /opt/dstreambolt/agent
# Update code and restart service
sudo systemctl restart ingest-api
```

### 4. Monitor and Debug

```bash
# Check all service health
cd examples
python check_services.py

# View logs
ssh -i ~/dstreambolt-access-key.pem ubuntu@<instance-ip>
sudo journalctl -u <service-name> -f

# Access UIs
# Jenkins: https://<alb>/jenkins
# Grafana: https://<alb>/grafana
# AKHQ: https://<alb>/kafkamgr
# Spark: https://<alb>/spark
```

## 🎯 Use Cases

### Real-Time Log Processing

1. **Ingest**: Applications send logs to ingestion endpoint
2. **Stream**: Kafka distributes logs to consumers
3. **Process**: Spark analyzes logs in real-time
4. **Monitor**: Grafana displays metrics and alerts

### Batch Analytics

1. **Collect**: Accumulate logs throughout the day
2. **Process**: Run Spark batch jobs for aggregations
3. **Store**: Save results to MySQL
4. **Visualize**: View trends in Grafana

### Error Detection

1. **Ingest**: Logs with error status codes
2. **Filter**: Spark identifies error patterns
3. **Alert**: Grafana triggers notifications
4. **Investigate**: AKHQ shows Kafka message details

## 🔐 Security Best Practices

1. **mTLS**: Always use client certificates for ingestion
2. **VPC**: Keep Kafka and Spark in private subnets
3. **Secrets**: Use AWS Secrets Manager for credentials
4. **Firewall**: Security groups restrict access
5. **Encryption**: Enable encryption at rest and in transit

## 📊 Cost Optimization

**Current Setup (Free Tier Eligible):**
- Ingest: t3.micro ($0/month with free tier)
- Kafka: t3.micro ($0/month with free tier)
- Spark: t3.micro ($0/month with free tier)
- DevOps: t3.small (~$15/month)
- ALB: ~$16/month
- **Total: ~$31/month** (or ~$1/month if all free tier)

**Tips:**
- Use t3.micro wherever possible
- Stop instances when not in use
- Use S3 for long-term log storage
- Consider Reserved Instances for production

## 📄 License

Proprietary - DStreamBolt Platform

---

**Last Updated**: December 7, 2025  
**Terraform Version**: 1.13.5  
**AWS Region**: ap-south-1 (Mumbai)  
**Repository Structure**: v2.0 (Reorganized)

**Ready to deploy!** 🚀

