# DStreamBolt Jenkins Jobs - Quick Reference

## 🚀 Quick Deploy Commands

### Deploy Ingestion Service

#### Single Server
```
Job: DStreamBolt-Deploy-Ingestion
TARGET_IPS: 13.201.43.125
GIT_BRANCH: main
RESTART_SERVICE: ✓
RUN_TESTS: ✓
```

#### Multiple Servers
```
TARGET_IPS: 13.201.43.125,52.66.123.45,15.206.146.37
```

### Deploy Spark Jobs

#### Streaming Mode
```
Job: DStreamBolt-Deploy-Spark
SPARK_MASTER_IPS: 43.205.94.74
KAFKA_BROKER: 10.0.10.101:9092
PROCESSING_MODE: streaming
GRACEFUL_SHUTDOWN: ✓
AUTO_START: ✓
```

#### Batch Mode
```
PROCESSING_MODE: batch
```

---

## 📋 Job Parameters

### Ingestion
- **TARGET_IPS** - Server IPs (comma-separated)
- **GIT_BRANCH** - Branch to deploy (default: main)
- **RESTART_SERVICE** - Restart after deploy (default: true)
- **RUN_TESTS** - Run health checks (default: true)

### Spark
- **SPARK_MASTER_IPS** - Spark master IPs (comma-separated)
- **KAFKA_BROKER** - Kafka address (default: 10.0.10.101:9092)
- **PROCESSING_MODE** - streaming or batch
- **GRACEFUL_SHUTDOWN** - Wait before killing jobs (default: true)
- **AUTO_START** - Start new job automatically (default: true)

---

## 🔍 Monitoring

### Check Service Status

```bash
# Ingestion
ssh ubuntu@<ip> sudo systemctl status ingest-api

# Spark
ssh ubuntu@<ip> ps aux | grep spark_processor.py
```

### View Logs

```bash
# Ingestion
ssh ubuntu@<ip> sudo journalctl -u ingest-api -f

# Spark
ssh ubuntu@<ip> tail -f /opt/spark/logs/spark-job-*.log
```

---

## 🔧 Troubleshooting

### Rollback Ingestion
```bash
ssh ubuntu@<ip>
cd /opt/dstreambolt/agent
sudo tar -xzf /opt/dstreambolt/backups/ingest-backup-<timestamp>.tar.gz
sudo systemctl restart ingest-api
```

### Rollback Spark
```bash
ssh ubuntu@<ip>
pkill -f spark_processor.py
cd /opt/dstreambolt/computations
sudo tar -xzf /opt/dstreambolt/backups/spark-backup-<timestamp>.tar.gz
./submit_spark_job.sh spark://<private-ip>:7077 10.0.10.101:9092 streaming 512m 512m
```

### Force Kill Spark Jobs
```bash
ssh ubuntu@<ip>
pkill -9 -f spark_processor.py
```

---

## 📞 Common Issues

| Issue | Solution |
|-------|----------|
| SSH timeout | Check security groups, verify key permissions |
| Service not starting | Check logs: `journalctl -u <service>` |
| Health check fails | Verify service is listening: `netstat -tlnp` |
| Job already running | Enable GRACEFUL_SHUTDOWN or manually kill |

---

For complete documentation, see: [jenkins/README.md](README.md)

