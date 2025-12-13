# DStreamBolt Infrastructure - Complete Setup Guide

## 🎯 Overview

This repository contains **modular, production-ready setup scripts** for all DStreamBolt infrastructure components. Each service can be installed independently or as part of a complete infrastructure deployment.

---

## 📁 Repository Structure

```
dstream_bolt/
├── setup_scripts/              # ⭐ Modular setup scripts
│   ├── setup_all.sh           # Master orchestrator
│   ├── setup_jenkins.sh       # Jenkins CI/CD
│   ├── setup_grafana.sh       # Grafana monitoring
│   ├── setup_mysql.sh         # MySQL database
│   ├── setup_kafka.sh         # Kafka + Zookeeper
│   ├── setup_spark_master.sh  # Spark Master
│   ├── setup_spark_worker.sh  # Spark Worker
│   ├── setup_ingestion.sh     # Ingestion API
│   ├── setup_akhq.sh          # AKHQ Kafka UI
│   └── README.md              # Detailed setup guide
│
├── utils/
│   └── login.sh               # ⭐ Enhanced SSH helper
│
├── terraform/                  # Infrastructure as Code
├── ingestion/                  # Ingestion service code
├── computations/               # Spark processing code
├── examples/                   # Example scripts
├── grafana/                    # Grafana dashboards
├── jenkins/                    # Jenkins pipelines
├── observability/              # Monitoring scripts
│
├── INFRASTRUCTURE_STATUS.md    # ⭐ Complete 15-point checklist
└── SETUP_COMPLETE_GUIDE.md     # This file

```

---

## 🚀 Quick Start

### Option 1: Complete Infrastructure Setup

```bash
# 1. SSH to DevOps node
./utils/login.sh devops

# 2. Copy setup scripts to the node
scp -i ~/dstreambolt-access-key.pem -r setup_scripts ubuntu@13.235.238.208:/tmp/

# 3. Run master setup script
sudo /tmp/setup_scripts/setup_all.sh

# 4. Select option 9 (All DevOps tools) or 10 (Complete Infrastructure)
```

### Option 2: Individual Component Setup

```bash
# SSH to target node
./utils/login.sh {devops|kafka|master|executor|ingest}

# Copy specific script
scp -i ~/dstreambolt-access-key.pem setup_scripts/setup_<component>.sh ubuntu@<ip>:/tmp/

# Run the script
sudo /tmp/setup_<component>.sh
```

---

## 📋 Setup Order for Complete Infrastructure

### 1. DevOps Node (13.235.238.208)

Install in this order:

```bash
# SSH to devops
./utils/login.sh devops

# Run individual scripts or use setup_all.sh
sudo ./setup_mysql.sh
sudo ./setup_jenkins.sh
sudo MYSQL_PASSWORD="DStreamBolt2025!" ./setup_grafana.sh
sudo KAFKA_BROKER="10.0.10.248:9092" ./setup_akhq.sh
```

**Services Installed:**
- ✅ MySQL (port 3306)
- ✅ Jenkins (port 8080)
- ✅ Grafana (port 3000)
- ✅ AKHQ (port 8081)

---

### 2. Kafka Node (10.0.10.248)

```bash
# SSH via devops (kafka is in private subnet)
./utils/login.sh kafka

# Run Kafka setup
sudo ./setup_kafka.sh
```

**Services Installed:**
- ✅ Zookeeper (port 2181)
- ✅ Kafka (port 9092)

**Topics Created:**
- `dstreambolt-logs` (3 partitions)
- `dstreambolt-metrics` (1 partition)

---

### 3. Spark Master Node (52.66.171.95)

```bash
# SSH to master
./utils/login.sh master

# Run Spark Master setup
sudo ./setup_spark_master.sh
```

**Services Installed:**
- ✅ Spark Master (port 7077, UI: 8080)
- ✅ Spark Worker (port 8081)

---

### 4. Spark Executor Node (65.0.74.255)

```bash
# SSH to executor
./utils/login.sh executor

# Run Spark Worker setup (connect to master)
sudo SPARK_MASTER_HOST="52.66.171.95" ./setup_spark_worker.sh
```

**Services Installed:**
- ✅ Spark Worker (port 8081)

---

### 5. Ingestion Node (13.232.206.53)

```bash
# SSH to ingest
./utils/login.sh ingest

# Copy application code
scp -i ~/dstreambolt-access-key.pem -r ingestion/app.py ingestion/requirements.txt ubuntu@13.232.206.53:/tmp/

# Run Ingestion setup
sudo KAFKA_BROKER="10.0.10.248:9092" \
     MYSQL_HOST="13.235.238.208" \
     MYSQL_PASSWORD="DStreamBolt2025!" \
     ./setup_ingestion.sh
```

**Services Installed:**
- ✅ Ingestion API (port 5000)
- ✅ Gunicorn (4 workers)

---

## 🔐 Default Credentials

| Service | URL | Username | Password | Notes |
|---------|-----|----------|----------|-------|
| **Jenkins** | http://13.235.238.208:8080 | admin | *See `/tmp/jenkins_initial_password.txt`* | Change on first login |
| **Grafana** | http://13.235.238.208:3000/grafana | admin | DStreamBolt2025! | Configurable |
| **AKHQ** | http://13.235.238.208:8081/kafkamgr | admin | DStreamBolt2025! | Full access |
| **AKHQ** | http://13.235.238.208:8081/kafkamgr | user | user123 | Read-only |
| **MySQL** | 13.235.238.208:3306 | root | DStreamBolt2025! | Root access |
| **MySQL** | 13.235.238.208:3306 | dstreambolt | DStreamBolt2025! | App access |

---

## 🔗 Service URLs

### Web Interfaces

| Service | URL | Description |
|---------|-----|-------------|
| Jenkins | http://13.235.238.208:8080 | CI/CD Server |
| Grafana | http://13.235.238.208:3000/grafana | Monitoring Dashboards |
| AKHQ | http://13.235.238.208:8081/kafkamgr | Kafka Management UI |
| Spark Master | http://52.66.171.95:8080 | Spark Master UI |
| Spark Worker (Master) | http://52.66.171.95:8081 | Worker UI |
| Spark Worker (Executor) | http://65.0.74.255:8081 | Worker UI |
| Ingestion Health | https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health | API Health |

### Service Endpoints

| Service | Endpoint | Protocol |
|---------|----------|----------|
| MySQL | 13.235.238.208:3306 | TCP |
| Kafka | 10.0.10.248:9092 | TCP |
| Zookeeper | 10.0.10.248:2181 | TCP |
| Spark Master | spark://52.66.171.95:7077 | Spark |
| Ingestion API | https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest | HTTPS |

---

## ✅ 15-Point Checklist Verification

Run these commands to verify each requirement:

### #1 - Jenkins Job Setup

```bash
./utils/login.sh devops
sudo systemctl status jenkins
curl -I http://localhost:8080/login
```

### #2 - MySQL Setup

```bash
./utils/login.sh devops
sudo systemctl status mysql
mysql -u root -p'DStreamBolt2025!' -e "SHOW DATABASES;"
```

### #3 - Spark Master & Executor

```bash
./utils/login.sh master
sudo systemctl status spark-master

./utils/login.sh executor
sudo systemctl status spark-worker
```

### #4 - Kafka Connectivity

```bash
./utils/login.sh kafka
sudo systemctl status kafka
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
```

### #5 - MySQL External Connectivity

```bash
# From any node
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics -e "SELECT 1;"
```

### #6 - Jenkins GitHub Integration

```bash
./utils/login.sh devops
sudo cat /var/lib/jenkins/.ssh/id_rsa.pub
# Add to GitHub → Settings → SSH Keys
```

### #7 - Kafka UI (AKHQ)

```bash
./utils/login.sh devops
sudo systemctl status akhq
curl -I http://localhost:8081/kafkamgr/
```

### #8 - Traffic Generation Script

```bash
cd examples
python3 continuous-log-sender.py --endpoint <url> --interval 30 --batch-size 1000
```

### #9 - MySQL Observability Tables

```bash
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics -e "SHOW TABLES;"
```

### #10 - Grafana Dashboards

```bash
# Access: http://13.235.238.208:3000/grafana
# Login: admin / DStreamBolt2025!
# Check dashboards
```

### #11 - Kafka Metrics Collection

```bash
./utils/login.sh kafka
sudo systemctl status kafka-metrics-collector

# Check metrics
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
  -e "SELECT * FROM kafka_metrics ORDER BY timestamp DESC LIMIT 5;"
```

### #12 - Spark Metrics

```bash
# Check in MySQL
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
  -e "SELECT * FROM spark_job_metrics ORDER BY timestamp DESC LIMIT 5;"
```

### #13 - Spark to MySQL Connectivity

```bash
./utils/login.sh master
# Test via Spark job or direct MySQL connection
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics -e "SELECT 1;"
```

### #14 - AWS Secrets Manager

```bash
# Check secrets
aws secretsmanager list-secrets --region ap-south-1
aws secretsmanager get-secret-value --secret-id dstreambolt/kafka --region ap-south-1
aws secretsmanager get-secret-value --secret-id dstreambolt/mysql --region ap-south-1
```

### #15 - Services Use Secrets Manager

```bash
./utils/login.sh ingest
sudo journalctl -u dstreambolt-ingest | grep "Secret loaded"
```

---

## 🔧 Maintenance & Operations

### Start/Stop Services

```bash
# Start a service
sudo systemctl start <service-name>

# Stop a service
sudo systemctl stop <service-name>

# Restart a service
sudo systemctl restart <service-name>

# Check status
sudo systemctl status <service-name>

# View logs
sudo journalctl -u <service-name> -f
```

### Service Names

- `jenkins`
- `grafana-server`
- `mysql`
- `akhq`
- `kafka`
- `zookeeper`
- `spark-master`
- `spark-worker`
- `dstreambolt-ingest`

### Update Configuration

Each service configuration can be updated:

- **Jenkins:** `/etc/systemd/system/jenkins.service.d/override.conf`
- **Grafana:** `/etc/grafana/grafana.ini`
- **MySQL:** `/etc/mysql/mysql.conf.d/dstreambolt.cnf`
- **Kafka:** `/opt/kafka/config/server.properties`
- **Spark:** `/opt/spark/conf/spark-defaults.conf`
- **Ingestion:** `/opt/dstreambolt/ingest/.env`
- **AKHQ:** `/opt/akhq/application.yml`

After config changes:

```bash
sudo systemctl daemon-reload  # If systemd service changed
sudo systemctl restart <service-name>
```

---

## 🧪 Testing

### Complete Health Check

```bash
#!/bin/bash
# Save as: health_check.sh

echo "🔍 DStreamBolt Infrastructure Health Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Jenkins
curl -s -o /dev/null -w "Jenkins:        %{http_code}\n" http://13.235.238.208:8080/login

# Grafana
curl -s -o /dev/null -w "Grafana:        %{http_code}\n" http://13.235.238.208:3000/grafana/

# AKHQ
curl -s -o /dev/null -w "AKHQ:           %{http_code}\n" http://13.235.238.208:8081/kafkamgr/

# Spark Master
curl -s -o /dev/null -w "Spark Master:   %{http_code}\n" http://52.66.171.95:8080/

# Spark Executor
curl -s -o /dev/null -w "Spark Executor: %{http_code}\n" http://65.0.74.255:8081/

# Ingestion
curl -s -o /dev/null -w "Ingestion:      %{http_code}\n" https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/health

# MySQL
mysql -h 13.235.238.208 -u dstreambolt -p'DStreamBolt2025!' -e "SELECT 'MySQL: OK';" 2>/dev/null || echo "MySQL: FAILED"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
```

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| `setup_scripts/README.md` | Detailed setup script usage guide |
| `INFRASTRUCTURE_STATUS.md` | Complete 15-point checklist with all details |
| `SETUP_COMPLETE_GUIDE.md` | This file - comprehensive setup guide |
| `terraform/README.md` | Terraform infrastructure documentation |

---

## 🆘 Troubleshooting

### Service Won't Start

1. Check service status:
   ```bash
   sudo systemctl status <service-name>
   ```

2. Check logs:
   ```bash
   sudo journalctl -u <service-name> -n 100 --no-pager
   ```

3. Check setup log:
   ```bash
   cat /var/log/<component>-setup.log
   ```

### Connectivity Issues

1. Test port connectivity:
   ```bash
   nc -zv <host> <port>
   ```

2. Check firewall/security groups:
   ```bash
   # On AWS
   aws ec2 describe-security-groups --region ap-south-1
   ```

3. Check service is listening:
   ```bash
   sudo netstat -tulpn | grep <port>
   ```

### Re-run Setup

All scripts are idempotent and safe to re-run:

```bash
sudo ./setup_scripts/setup_<component>.sh
# Answer 'y' when prompted to reinstall
```

---

## 🎓 Best Practices

1. **Always use sudo** - All setup scripts require root privileges
2. **Check logs** - Each script produces detailed logs in `/var/log/`
3. **Verify after setup** - Run health checks after installation
4. **Backup before changes** - Backup configs before modifying
5. **Use environment variables** - For automation and CI/CD
6. **Keep credentials secure** - Change default passwords in production
7. **Monitor services** - Use Grafana dashboards for ongoing monitoring
8. **Regular updates** - Keep services updated for security

---

## 📞 Support & Resources

- **Setup logs:** `/var/log/*-setup.log`
- **Master logs:** `/var/log/dstreambolt-setup/master_setup_*.log`
- **Service logs:** `journalctl -u <service-name>`
- **Configuration files:** See "Update Configuration" section above

---

## ✅ Success Criteria

After setup, you should have:

- ✅ All 15 requirements from checklist working
- ✅ All services running (`systemctl status` shows active)
- ✅ All web UIs accessible
- ✅ Jenkins can connect to GitHub
- ✅ Grafana can query MySQL
- ✅ AKHQ can see Kafka topics
- ✅ Spark workers connected to master
- ✅ Ingestion API can write to Kafka
- ✅ Spark jobs can write to MySQL
- ✅ Metrics collection working
- ✅ Dashboards showing data

---

## 🎉 Next Steps

After successful setup:

1. **Configure Jenkins jobs** - Import pipelines from `jenkins/` directory
2. **Import Grafana dashboards** - From `grafana/` directory
3. **Start traffic generation** - Run continuous log sender
4. **Monitor in Grafana** - Watch real-time metrics
5. **Deploy Spark jobs** - Use Jenkins pipeline
6. **Customize as needed** - Adjust configs for your use case

---

**Last Updated:** December 13, 2025  
**Version:** 1.0  
**Region:** ap-south-1  
**All setup scripts tested and verified** ✅

