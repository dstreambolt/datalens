# 🚀 DStreamBolt One-Click Deployment

Complete infrastructure automation with **zero manual intervention**.

## ✨ Features

- ✅ **One-Click Deployment** - Single command creates entire infrastructure
- ✅ **Auto-Configuration** - All services configured automatically via user_data
- ✅ **DNS Optional** - Works immediately with ALB, add custom domain later
- ✅ **Health Checks** - Automated verification of all services
- ✅ **Secure by Default** - Auto-generated passwords, SSH keys, certificates
- ✅ **Production Ready** - Kafka, Spark, Ingestion, Jenkins, Grafana, MySQL

---

## 🎯 Quick Start

### Option 1: Deploy WITHOUT DNS (Fastest)

```bash
cd terraform
./deploy.sh
```

**Access immediately via:**
- https://dstreambolt-alb-[random].ap-south-1.elb.amazonaws.com/

### Option 2: Deploy WITH DNS

```bash
cd terraform
./deploy.sh --with-dns
```

Then add the DNS CNAME record shown in the output.

**Access via custom domain:**
- https://dstreambolt.click/
- https://jenkins.dstreambolt.click/
- https://grafana.dstreambolt.click/

---

## 📋 Prerequisites

1. **AWS Account** with credentials configured
2. **Terraform** >= 1.5.0
3. **AWS CLI** >= 2.0

```bash
# Check prerequisites
terraform version
aws --version
aws sts get-caller-identity
```

---

## 🏗️ What Gets Deployed

### Infrastructure

| Component | Instance Type | Purpose |
|-----------|--------------|---------|
| **DevOps Node** | t3.small | Jenkins, Grafana, MySQL, AKHQ, Nginx |
| **Kafka** | t3.micro | Kafka + Zookeeper (private) |
| **Spark Master** | t3.small | Spark Master + Worker |
| **Spark Executor** | t3.small | Additional Spark Worker |
| **Ingestion** | t3.micro | Log ingestion API |
| **ALB** | - | Load balancer with SSL |

### Services Automatically Configured

#### DevOps Node
- ✅ Jenkins (CI/CD) - Port 8080
- ✅ Grafana (Monitoring) - Port 3000
- ✅ MySQL (Metrics DB) - Port 3306
- ✅ AKHQ (Kafka UI) - Port 8081
- ✅ Nginx (Reverse Proxy) - Port 80

#### Kafka Node
- ✅ Zookeeper - Port 2181
- ✅ Kafka Broker - Port 9092
- ✅ Topics: `dstreambolt-logs`, `dstreambolt-metrics`

#### Spark Cluster
- ✅ Spark Master UI - Port 8080
- ✅ Spark Worker UI - Port 8081
- ✅ Spark Submit - Port 7077

#### Ingestion Service
- ✅ Flask API - Port 5000
- ✅ Gunicorn (4 workers)
- ✅ Health endpoint: `/health`
- ✅ Ingest endpoint: `/ingest`

---

## 📖 Deployment Details

### Step-by-Step Process

1. **Prerequisites Check**
   - Validates Terraform, AWS CLI, credentials
   - Creates SSH key pair if needed
   - Generates secure MySQL password

2. **Terraform Execution**
   ```bash
   terraform init     # Initialize providers
   terraform validate # Validate configuration
   terraform plan     # Preview changes
   terraform apply    # Create infrastructure
   ```

3. **User Data Scripts** (Automatic)
   - DevOps: Installs Jenkins, Grafana, MySQL, AKHQ, Nginx
   - Kafka: Installs Kafka, Zookeeper, creates topics
   - Spark: Installs Spark Master + Worker
   - Ingestion: Installs Python app with Gunicorn

4. **Post-Deployment** (5-10 minutes)
   - Services start automatically
   - MySQL tables created
   - Nginx configured
   - Security groups configured

5. **Verification**
   ```bash
   ./verify.sh  # Check all services
   ```

---

## 🔐 Security

### Automatically Configured

- ✅ SSH key pair generated and stored securely
- ✅ MySQL password randomly generated (32 chars)
- ✅ AWS Secrets Manager integration
- ✅ Security groups with proper ingress/egress rules
- ✅ SSL certificate for ALB (self-signed for *.elb.amazonaws.com)
- ✅ Optional: ACM certificate for custom domain

### Access Control

- DevOps, Spark: **Public** (SSH only with key)
- Kafka: **Private** (accessible only from VPC)
- Ingestion: **Public** (behind ALB)
- All HTTP traffic: **Via ALB only**

---

## 🔍 Verification

### Health Check Script

```bash
cd terraform
./verify.sh
```

Checks:
- ✅ EC2 instances running
- ✅ ALB operational
- ✅ All services responding
- ✅ Ports listening correctly
- ✅ Kafka topics created
- ✅ Spark cluster connected

### Manual Verification

```bash
# Test ALB
curl -I https://$(terraform output -raw alb_dns_name)/

# SSH to DevOps
ssh -i ~/dstreambolt-access-key.pem ubuntu@$(terraform output -json direct_access | jq -r .devops_ip)

# Check Jenkins
systemctl status jenkins

# Check Grafana
systemctl status grafana-server

# Check Kafka topics
ssh ubuntu@<kafka-ip> '/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092'
```

---

## 🌐 DNS Configuration (Optional)

### Automatic DNS Setup

If you deployed with `--with-dns`:

1. Script requests ACM certificate automatically
2. Shows DNS CNAME record to add:
   ```
   Type:  CNAME
   Name:  _e5a93565e3c0c146efa9468fbe176157
   Value: _884793f939ee503829710ba40dcae37d.jkddzztszm.acm-validations.aws.
   ```

3. Add to HostAsia DNS
4. Wait 10-15 minutes for validation
5. Certificate attached to ALB automatically

### Manual DNS Setup

```bash
cd scripts
./setup_domain_ssl.sh
```

Follow instructions to:
- Request ACM certificate
- Add DNS validation record
- Attach certificate to ALB

---

## 📊 Access Information

### After Deployment

All credentials and URLs shown in output:

```bash
# View all outputs
terraform output

# Specific outputs
terraform output alb_url
terraform output -json credentials
terraform output -json direct_access
```

### Default Credentials

| Service | Username | Password | Notes |
|---------|----------|----------|-------|
| Jenkins | admin | `terraform output jenkins_password` | Auto-generated |
| Grafana | admin | `terraform output grafana_password` | Auto-generated |
| MySQL | root | `terraform output mysql_root_password` | Auto-generated |
| AKHQ | admin | DStreamBolt2025! | Configured in user_data |

---

## 🛠️ Maintenance

### Update Infrastructure

```bash
# Make changes to .tf files
terraform plan
terraform apply
```

### Destroy Infrastructure

```bash
terraform destroy
```

**Warning:** This deletes everything. Backup data first!

### Restart Services

```bash
# SSH to DevOps node
ssh -i ~/dstreambolt-access-key.pem ubuntu@<devops-ip>

# Restart specific service
sudo systemctl restart jenkins
sudo systemctl restart grafana-server
sudo systemctl restart mysql
```

### View Logs

```bash
# Jenkins logs
sudo journalctl -u jenkins -f

# Grafana logs
sudo journalctl -u grafana-server -f

# Ingestion service logs
ssh ubuntu@<ingest-ip>
sudo journalctl -u dstreambolt-ingest -f

# Kafka logs
ssh ubuntu@<kafka-ip>
tail -f /opt/kafka/logs/server.log
```

---

## 🔧 Troubleshooting

### Services Not Starting

**Check user_data completion:**
```bash
ssh ubuntu@<instance-ip>
tail -100 /var/log/cloud-init-output.log
```

**Manually run user_data script:**
```bash
# On DevOps node
sudo bash /var/lib/cloud/instance/scripts/part-001
```

### SSL Certificate Issues

**Check certificate status:**
```bash
aws acm describe-certificate \
  --certificate-arn <arn> \
  --region ap-south-1 \
  --query 'Certificate.Status'
```

**Re-run DNS setup:**
```bash
cd scripts
./setup_domain_ssl.sh
```

### Can't Access Services

**Check ALB target health:**
```bash
aws elbv2 describe-target-health \
  --target-group-arn <arn> \
  --region ap-south-1
```

**Check security groups:**
```bash
# Verify ports are open
ssh ubuntu@<ip> 'sudo netstat -tlnp | grep LISTEN'
```

### Kafka Connection Issues

```bash
# Check Kafka is listening on correct IP
ssh ubuntu@<kafka-ip>
grep advertised.listeners /opt/kafka/config/server.properties

# Should show: advertised.listeners=PLAINTEXT://<private-ip>:9092
```

---

## 📂 File Structure

```
terraform/
├── deploy.sh              # 🎯 One-click deployment script
├── verify.sh              # ✅ Health check script
├── main.tf                # Main Terraform config
├── variables.tf           # Variable definitions
├── outputs.tf             # Output definitions
├── terraform.tfvars       # Your configuration (auto-generated)
├── modules/
│   ├── networking/        # VPC, subnets, security groups
│   ├── alb/               # Application Load Balancer
│   ├── devops/            # DevOps node module
│   ├── kafka/             # Kafka node module
│   ├── compute/           # Spark cluster module
│   └── ingest/            # Ingestion service module
└── user_data/
    ├── devops.sh          # DevOps node setup script
    ├── kafka.sh           # Kafka setup script (idempotent!)
    ├── spark_master.sh    # Spark master setup
    ├── spark_executor.sh  # Spark worker setup
    └── ingest.sh          # Ingestion service setup

scripts/
└── setup_domain_ssl.sh    # Optional DNS/SSL configuration

observability/
├── create_observability_tables.sql   # MySQL schema
├── deploy_kafka_collector.sh         # Kafka metrics
└── grafana/                           # Grafana dashboards
```

---

## 🎯 What Makes This "One-Click"

### Before (Manual Process)
1. Run terraform apply
2. SSH to each instance
3. Run setup scripts manually
4. Configure MySQL
5. Create database tables
6. Set up security groups
7. Configure Nginx
8. Test each service
9. Fix issues manually
10. Repeat...

### After (Automated)
```bash
./deploy.sh
# ☕ Get coffee (5-10 minutes)
# ✅ Everything ready!
```

### Key Features

- **Idempotent Scripts** - Can run multiple times safely
- **Automatic Retries** - Services restart if failed
- **Dependency Management** - Scripts wait for dependencies
- **Error Handling** - Graceful fallbacks
- **Status Reporting** - Clear progress indicators
- **Rollback Safe** - terraform destroy cleans everything

---

## 💡 Pro Tips

### Speed Up Deployment

```bash
# Skip expensive resources during development
terraform apply -var="skip_expensive=true"
```

### Parallel Operations

```bash
# Terraform automatically parallelizes when possible
# Just run: ./deploy.sh
```

### Cost Optimization

- Use `t3.micro` for non-production
- Stop instances when not in use:
  ```bash
  aws ec2 stop-instances --instance-ids <id> --region ap-south-1
  ```

### Backup Before Destroy

```bash
# Export terraform state
terraform state pull > terraform.tfstate.backup

# Backup MySQL
ssh ubuntu@<devops-ip>
mysqldump -u root -p dstreambolt_metrics > backup.sql
```

---

## 🎉 Success Criteria

After running `./deploy.sh`, you should see:

✅ All EC2 instances **running**  
✅ ALB responding with **HTTP 200**  
✅ Jenkins accessible at **/jenkins**  
✅ Grafana accessible at **/grafana**  
✅ Spark UI showing **master + workers**  
✅ Kafka topics **created and listed**  
✅ MySQL **accepting connections**  
✅ Ingestion API returning **health OK**  

Run `./verify.sh` to check all criteria automatically!

---

## 📞 Need Help?

**Check these first:**
1. `./verify.sh` - Automated health check
2. `/var/log/cloud-init-output.log` - User data script output
3. `journalctl -u <service>` - Service logs
4. AWS Console - EC2, ALB, VPC sections

**Common Issues:**
- Services still starting? Wait 10 minutes, check again
- Port not listening? Check security groups
- Can't SSH? Verify key pair and public IP
- 502 Bad Gateway? Service not started yet

---

## 🚀 Ready to Deploy?

```bash
cd terraform
./deploy.sh

# With DNS (optional)
./deploy.sh --with-dns
```

That's it! 🎉

Your complete DStreamBolt infrastructure will be ready in ~10 minutes with:
- Load balancer
- 5 EC2 instances
- Kafka cluster
- Spark cluster
- All services configured
- Ready to process data!

