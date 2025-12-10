# DStreamBolt Complete Pipeline - Deployment Guide

## 🎯 Overview

This guide walks you through deploying the complete DStreamBolt real-time analytics pipeline:
- **Ingestion** → **Kafka** → **Spark Streaming** → **MySQL** → **Grafana**

## 📋 Prerequisites

✅ All infrastructure is deployed (Kafka, Spark, MySQL, Grafana)  
✅ MySQL tables are created  
✅ Grafana dashboard is imported  
✅ Jenkins pipeline is configured  

## 🚀 Step-by-Step Deployment

### Step 1: Set Up MySQL Tables

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/terraform
./setup_mysql_tables.sh
```

**Expected Output:**
- ✅ status_summary table created
- ✅ endpoint_summary table created
- ✅ error_analysis table created
- ✅ hourly_summary table created
- ✅ realtime_metrics table created

### Step 2: Set Up Grafana Dashboard

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/terraform
chmod +x setup_grafana_dashboard.sh
./setup_grafana_dashboard.sh
```

**Expected Output:**
- ✅ MySQL datasource configured
- ✅ Dashboard imported
- 📊 Dashboard URL provided

### Step 3: Build and Deploy Spark Application

```bash
# Build the Scala application
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/computations
sbt clean assembly

# Commit and push changes
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
git add -A
git commit -m "Add streaming mode with MySQL sinks and Grafana dashboard"
git push
```

### Step 4: Deploy via Jenkins (Streaming Mode)

1. Open Jenkins: `http://13.232.132.240:8081`
2. Go to **DStreamBolt-Deploy-Spark-Scala** pipeline
3. Click **Build with Parameters**
4. Set parameters:
   - **SPARK_MASTER_IPS**: `10.0.1.199` (or use existing)
   - **GIT_BRANCH**: `release/v1.0.1` (or your branch)
   - **REMOTE_USER**: `ubuntu`
   - **KAFKA_BROKER**: `10.0.10.101:9092`
   - **PROCESSING_MODE**: `streaming` ⭐ (KEY: Change from batch!)
   - **SPARK_DRIVER_MEMORY**: `512m`
   - **SPARK_EXECUTOR_MEMORY**: `512m`
   - **AUTO_START**: `true`
5. Click **Build**

### Step 5: Send Test Data to Kafka

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/examples

# Send logs to ingestion API
python3 02-send-to-ingest.py \
  --alb-url https://dstreambolt-alb-841612552.ap-south-1.elb.amazonaws.com/ingest \
  --no-verify \
  logs/access.log
```

### Step 6: Verify Streaming is Working

#### Check Spark Job Status

```bash
# SSH to Spark Master
ssh -i ~/dstreambolt-access-key.pem ubuntu@15.206.123.221

# Check if job is running
ps aux | grep SparkProcessor

# Check Spark logs
tail -f /opt/spark/logs/spark-job.log

# Should see output like:
# 📊 Writing status aggregations batch 0 to MySQL
# 📊 Writing endpoint aggregations batch 1 to MySQL
```

#### Check MySQL Data

```bash
# SSH to DevOps node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240

# Query MySQL
mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# Check data is flowing
SELECT COUNT(*) FROM status_summary;
SELECT COUNT(*) FROM endpoint_summary;

# Check latest data
SELECT * FROM status_summary ORDER BY window_start DESC LIMIT 5;
SELECT * FROM endpoint_summary ORDER BY window_start DESC LIMIT 5;
```

#### Check Grafana Dashboard

1. Open: `http://13.232.132.240:3000`
2. Login: `admin` / `DStreamBolt2025!`
3. Navigate to **DStreamBolt Real-Time Analytics** dashboard
4. You should see:
   - ✅ Requests Per Minute chart updating
   - ✅ Error Rate chart showing data
   - ✅ Status Code Distribution pie chart
   - ✅ Real-time metrics updating every 10 seconds

## 🎨 Dashboard Panels

### 1. Requests Per Minute
- Shows total requests over time
- Updates every window (default: 30 seconds)
- Time range: Last 1 hour

### 2. Error Rate %
- Percentage of 4xx and 5xx errors
- Color-coded thresholds:
  - Green: < 5%
  - Yellow: 5-10%
  - Red: > 10%

### 3. Status Code Distribution
- Pie chart of HTTP status codes
- Shows: 200, 201, 400, 404, 500, 503, etc.

### 4. Average Response Time
- Gauge showing current avg response time
- Thresholds:
  - Green: < 0.5s
  - Yellow: 0.5-1.0s
  - Orange: 1.0-2.0s
  - Red: > 2.0s

### 5. Current Requests/sec
- Real-time requests per second
- Based on last 1 minute of data

### 6. Top 10 Slowest Endpoints
- Table with avg, p95, p99 response times
- Sortable by any column
- Helps identify performance bottlenecks

### 7. Top 10 Most Requested Endpoints
- Horizontal bar chart
- Shows endpoint + method
- Based on request count

### 8. Response Time Percentiles
- Line chart with avg, p95, p99
- Helps understand response time distribution
- Time range: Last 15 minutes

### 9. Error Analysis
- Table showing all errors
- Status code, endpoint, method, error count
- Sortable and filterable

## 🔧 Configuration

### Change Window Duration

Edit the window duration in the Spark job parameters:

```bash
# In Jenkins pipeline or manual spark-submit
--window-duration "1 minute"  # Options: 10 seconds, 30 seconds, 1 minute, 5 minutes
```

### Change Refresh Rate

In Grafana dashboard settings:
1. Click dashboard settings (gear icon, top right)
2. Change **Refresh** from `10s` to desired value
3. Options: 5s, 10s, 30s, 1m, 5m

### Add Custom Panels

See `grafana/SETUP_GUIDE.md` for examples of custom SQL queries and panel configurations.

## 🐛 Troubleshooting

### No Data in Grafana

1. **Check Spark streaming job is running:**
   ```bash
   ssh ubuntu@15.206.123.221
   ps aux | grep SparkProcessor | grep streaming
   ```

2. **Check MySQL tables have data:**
   ```bash
   mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics \
     -e "SELECT COUNT(*) FROM status_summary;"
   ```

3. **Check Grafana datasource:**
   - Go to Configuration → Data Sources
   - Click "DStreamBolt-MySQL"
   - Click "Save & Test"

### Streaming Job Stops

The streaming job should run continuously. If it stops:

1. **Check Spark logs:**
   ```bash
   tail -100 /opt/spark/logs/spark-job.log
   ```

2. **Restart via Jenkins:**
   - Re-run the pipeline with `--mode streaming`

3. **Common issues:**
   - Kafka connection lost → Check Kafka is running
   - MySQL connection timeout → Check MySQL is accepting connections
   - Out of memory → Increase driver/executor memory

### High Memory Usage

If Spark uses too much memory:

1. **Reduce window duration:**
   ```
   --window-duration "10 seconds"  # Smaller windows = less memory
   ```

2. **Increase checkpoint cleanup:**
   ```scala
   // In SparkProcessor.scala
   .config("spark.cleaner.referenceTracking.cleanCheckpoints", "true")
   ```

3. **Limit data retention:**
   ```sql
   -- Clean up old data in MySQL
   DELETE FROM status_summary WHERE window_start < NOW() - INTERVAL 7 DAY;
   DELETE FROM endpoint_summary WHERE window_start < NOW() - INTERVAL 7 DAY;
   ```

## 📊 Understanding the Data Flow

```
┌──────────────┐
│  Ingestion   │  Receives HTTP logs
│   Service    │  Compresses and sends to Kafka
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    Kafka     │  Topic: dstreambolt-logs
│    Broker    │  Stores raw log messages
└──────┬───────┘
       │
       ▼
┌──────────────┐
│    Spark     │  Streaming job reads every window
│  Streaming   │  Aggregates by status, endpoint, method
└──────┬───────┘
       │
       ├─────────────────────┐
       │                     │
       ▼                     ▼
┌──────────────┐    ┌─────────────────┐
│status_summary│    │endpoint_summary │
│   (MySQL)    │    │     (MySQL)     │
└──────┬───────┘    └────────┬────────┘
       │                     │
       └─────────┬───────────┘
                 │
                 ▼
          ┌──────────────┐
          │   Grafana    │  Real-time dashboard
          │  Dashboard   │  Updates every 10s
          └──────────────┘
```

## 🎯 Success Criteria

✅ Spark streaming job runs continuously  
✅ MySQL tables receive new rows every window  
✅ Grafana dashboard updates in real-time  
✅ All panels show data  
✅ No errors in Spark logs  
✅ No connection issues to Kafka/MySQL  

## 📈 Next Steps

1. **Set up alerting:** Configure Grafana alerts for error rate, response time
2. **Data retention:** Set up cron jobs to archive/delete old data
3. **Scale up:** Add more Spark executors if needed
4. **Custom analytics:** Add more aggregations and panels
5. **Export dashboards:** Save dashboard JSON for backup

## 🔗 Quick Links

- **Grafana:** http://13.232.132.240:3000
- **Jenkins:** http://13.232.132.240:8081
- **Spark Master UI:** http://15.206.123.221:8080
- **Spark Worker UI:** http://15.207.108.16:8081
- **Kafka Manager:** http://13.232.132.240:9000/kafkamgr/

## 📞 Support

For issues:
1. Check logs in `/opt/spark/logs/`
2. Verify MySQL connectivity
3. Check Kafka topics have messages
4. Review Grafana datasource connection

---

**🎉 Congratulations! You now have a fully operational real-time analytics pipeline!**

