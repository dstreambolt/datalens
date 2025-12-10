# DStreamBolt Quick Reference

## 🚀 Quick Start Commands

### Start Streaming Mode (Jenkins)
```
1. Open: http://13.232.132.240:8081
2. Pipeline: DStreamBolt-Deploy-Spark-Scala
3. Set: PROCESSING_MODE = "streaming"
4. Click Build
```

### View Grafana Dashboard
```
URL: http://13.232.132.240:3000
Login: admin / DStreamBolt2025!
Dashboard: DStreamBolt Real-Time Analytics
```

### Send Test Data
```bash
cd examples
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --no-verify logs/access.log
```

## 📊 MySQL Quick Queries

```sql
-- Connect to MySQL
mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

-- Check streaming data
SELECT COUNT(*) FROM status_summary;
SELECT COUNT(*) FROM endpoint_summary;

-- Latest aggregations
SELECT * FROM status_summary ORDER BY window_start DESC LIMIT 10;
SELECT * FROM endpoint_summary ORDER BY window_start DESC LIMIT 10;

-- Top endpoints by request count
SELECT endpoint, method, SUM(request_count) as total 
FROM endpoint_summary 
GROUP BY endpoint, method 
ORDER BY total DESC 
LIMIT 10;

-- Error rate analysis
SELECT status, SUM(request_count) as errors 
FROM status_summary 
WHERE status >= 400 
GROUP BY status 
ORDER BY errors DESC;
```

## 🔧 Troubleshooting Commands

### Check Spark Job Status
```bash
ssh ubuntu@15.206.123.221
ps aux | grep SparkProcessor
tail -f /opt/spark/logs/spark-job.log
```

### Check Kafka Topics
```bash
ssh ubuntu@10.0.10.101
/opt/kafka/bin/kafka-topics.sh --bootstrap-server localhost:9092 --list
/opt/kafka/bin/kafka-console-consumer.sh --bootstrap-server localhost:9092 --topic dstreambolt-logs --from-beginning --max-messages 5
```

### Check Grafana Status
```bash
ssh ubuntu@13.232.132.240
sudo systemctl status grafana-server
sudo journalctl -u grafana-server -f
```

### Check MySQL Connection
```bash
# From Spark executor
nc -zv 10.0.1.61 3306

# Login to MySQL
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics
```

## 📡 Service Endpoints

| Service | URL | Notes |
|---------|-----|-------|
| Grafana | http://13.232.132.240:3000 | admin / DStreamBolt2025! |
| Jenkins | http://13.232.132.240:8081 | CI/CD |
| Spark Master UI | http://15.206.123.221:8080 | Job monitoring |
| Spark Worker UI | http://15.207.108.16:8081 | Executor status |
| Kafka Manager | http://13.232.132.240:9000/kafkamgr/ | Topic management |
| MySQL | 10.0.1.61:3306 | dstreambolt / DStreamBolt2025! |

## 🗄️ MySQL Tables

| Table | Purpose | Key Columns |
|-------|---------|-------------|
| status_summary | Status code aggregations | status, request_count, avg_response_time |
| endpoint_summary | Endpoint performance | endpoint, method, p95_response_time, unique_ips |
| error_analysis | Error tracking | status, endpoint, error_count |
| spark_results | Batch processing results | All raw fields |
| hourly_summary | Long-term analytics | hour_start, total_requests |
| realtime_metrics | Dashboard KPIs | metric_name, metric_value |

## 🎨 Grafana Panel SQL Examples

### Requests Over Time
```sql
SELECT 
  window_start as time,
  SUM(request_count) as value
FROM status_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start 
ORDER BY window_start
```

### Error Rate %
```sql
SELECT 
  window_start as time,
  SUM(CASE WHEN status >= 400 THEN request_count ELSE 0 END) * 100.0 / SUM(request_count) as value
FROM status_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start
```

### Top Slowest Endpoints
```sql
SELECT 
  endpoint,
  method,
  ROUND(AVG(avg_response_time), 3) as avg_time,
  SUM(request_count) as requests
FROM endpoint_summary 
WHERE window_start >= NOW() - INTERVAL 15 MINUTE
GROUP BY endpoint, method 
ORDER BY avg_time DESC 
LIMIT 10
```

## 🔄 Common Operations

### Restart Streaming Job
```bash
# Stop current job
ssh ubuntu@15.206.123.221
pkill -f SparkProcessor

# Start via Jenkins with --mode streaming
```

### Clean Up Old Data
```sql
DELETE FROM status_summary WHERE window_start < NOW() - INTERVAL 7 DAY;
DELETE FROM endpoint_summary WHERE window_start < NOW() - INTERVAL 7 DAY;
```

### Change Window Duration
```
Update Jenkins parameter or manual spark-submit:
--window-duration "1 minute"  # Options: 10 seconds, 30 seconds, 1 minute, 5 minutes
```

### Export Grafana Dashboard
```bash
curl -u admin:DStreamBolt2025! \
  http://13.232.132.240:3000/api/dashboards/uid/aed82fe7-5cc9-4146-b8c4-51bf88feef6e \
  | jq > dashboard-backup.json
```

## 📞 Emergency Procedures

### Pipeline Stopped Working
1. Check Kafka is running: `ssh ubuntu@10.0.10.101 && sudo systemctl status kafka`
2. Check Spark job: `ps aux | grep SparkProcessor`
3. Check MySQL: `mysql -h 10.0.1.61 -u dstreambolt -p`
4. Restart streaming job via Jenkins

### No Data in Grafana
1. Verify datasource: Configuration → Data Sources → Test
2. Check MySQL has data: `SELECT COUNT(*) FROM status_summary;`
3. Verify time range in dashboard
4. Check Grafana logs: `sudo journalctl -u grafana-server -f`

### High Memory Usage
1. Reduce window duration: `--window-duration "10 seconds"`
2. Increase checkpoint cleanup frequency
3. Add more executors or increase memory

## 🔍 Observability & Monitoring

### Check Ingestion Metrics
```sql
-- Recent ingestion requests
SELECT * FROM ingestion_requests ORDER BY timestamp DESC LIMIT 10;

-- Bundle processing performance
SELECT 
    AVG(total_processing_time_ms) as avg_ms,
    AVG(kafka_write_time_ms) as kafka_ms
FROM bundle_processing 
WHERE timestamp >= NOW() - INTERVAL 1 HOUR;

-- Failed bundles
SELECT * FROM failed_bundles WHERE resolved = FALSE;
```

### Check Kafka Health
```sql
-- Consumer lag
SELECT * FROM kafka_consumer_lag ORDER BY timestamp DESC LIMIT 10;

-- Topic metrics
SELECT * FROM kafka_topic_metrics ORDER BY timestamp DESC;
```

### Check Spark Processing
```sql
-- Processing metrics
SELECT * FROM spark_processing_metrics ORDER BY timestamp DESC LIMIT 10;

-- Failed records
SELECT * FROM spark_failed_records ORDER BY timestamp DESC LIMIT 10;

-- Job status
SELECT * FROM spark_job_status WHERE status = 'running';
```

### DevOps Dashboard
**URL:** http://13.232.132.240:3000/d/devops-dashboard

**Features:**
- Pipeline health across all layers
- Error tracking and drill-down
- Performance metrics
- Failed operations monitoring

## 🔗 Important Files

- **Spark Code**: `computations/src/main/scala/com/dstreambolt/processor/SparkProcessor.scala`
- **SQL Schema**: `terraform/create_mysql_tables.sql`
- **Observability Schema**: `observability/create_observability_tables.sql`
- **Observability Guide**: `observability/IMPLEMENTATION_SUMMARY.md`
- **Dashboard JSON**: `grafana/dstreambolt-dashboard.json`
- **Setup Guides**: `DEPLOYMENT_GUIDE.md`, `grafana/SETUP_GUIDE.md`
- **Jenkins Pipeline**: `jenkins/deploy-prebuilt-scala-spark.jenkinsfile`

---

**Need Help?** Check `DEPLOYMENT_GUIDE.md` for detailed instructions!
**For Observability:** Check `observability/IMPLEMENTATION_SUMMARY.md`!

