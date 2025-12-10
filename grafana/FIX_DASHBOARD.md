# Fix Grafana Dashboard - Complete Guide

## 🔴 Problem

Grafana shows error: **"Table 'dstreambolt_metrics.log_metrics' doesn't exist"**

This happens because:
1. Old dashboard uses table names that don't exist
2. New observability tables have different names

## ✅ Solution

### Step 1: Create Observability Tables (if not done)

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/observability
./setup_observability.sh
```

### Step 2: Configure MySQL Data Source in Grafana

1. **Access Grafana:**
   ```bash
   open http://13.232.132.240:3000
   # Login: admin / DStreamBolt2025!
   ```

2. **Add/Update MySQL Data Source:**
   - Go to: **Configuration** (⚙️) → **Data Sources**
   - Click **Add data source** or edit existing MySQL source
   - Configure:
     - **Name:** `DStreamBolt MySQL`
     - **Host:** `10.0.1.61:3306`
     - **Database:** `dstreambolt_metrics`
     - **User:** `dstreambolt`
     - **Password:** `DStreamBolt2025!`
   - Click **Save & Test**

### Step 3: Import New DevOps Dashboard

**Option A: Via UI (Recommended)**

1. Go to **Dashboards** → **Import**
2. Click **Upload JSON file**
3. Select: `/Users/skalaise/apps/cloud/terraform/dstream_bolt/grafana/devops-dashboard.json`
4. Select data source: **DStreamBolt MySQL**
5. Click **Import**

**Option B: Via API**

```bash
# Copy dashboard JSON to DevOps node
scp -i ~/dstreambolt-access-key.pem \
  grafana/devops-dashboard.json \
  ubuntu@13.232.132.240:/tmp/

# SSH to DevOps node
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240

# Import via API
curl -X POST http://localhost:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -u admin:DStreamBolt2025! \
  -d @/tmp/devops-dashboard.json
```

### Step 4: Verify Dashboard

The new dashboard includes:

✅ **Ingestion Metrics:**
- Requests per minute
- Success vs Failed rate
- Processing time breakdown
- Bundle size and line counts

✅ **Kafka Metrics:**
- Records written/failed
- Consumer lag by topic
- Topic health
- Broker metrics

✅ **Failed Operations:**
- Failed bundles table
- Error details
- Failure stages

✅ **Real-Time Counters:**
- Total requests
- Successful bundles
- Failed bundles
- Records processed

✅ **Spark Metrics (when available):**
- Processing metrics
- Failed records
- Job status

## 🔧 Troubleshooting

### Issue: "Table doesn't exist" error

**Check tables exist:**
```sql
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

SHOW TABLES LIKE '%ingestion%';
SHOW TABLES LIKE '%kafka%';
```

**If tables missing, create them:**
```bash
cd observability
./setup_observability.sh
```

### Issue: "No data in dashboard"

**Check if services are collecting data:**

1. **Ingestion service:**
   ```bash
   ssh ubuntu@13.201.43.125
   sudo systemctl status dstreambolt-ingest
   
   # Test endpoint
   curl http://localhost:5000/metrics
   ```

2. **Kafka collector:**
   ```bash
   aws ssm start-session --target i-0bdf20dd0b5e1cc81 --region ap-south-1
   sudo systemctl status kafka-metrics-collector
   tail -f /var/log/dstreambolt/kafka-metrics.log
   ```

3. **Check MySQL:**
   ```sql
   SELECT COUNT(*) FROM ingestion_requests;
   SELECT COUNT(*) FROM kafka_topic_metrics;
   SELECT * FROM ingestion_realtime_metrics;
   ```

### Issue: "Data source error"

**Test MySQL connection from Grafana host:**
```bash
ssh ubuntu@13.232.132.240
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics -e "SELECT 1"
```

**Check MySQL allows remote connections:**
```sql
-- On MySQL host (13.232.132.240)
SELECT user, host FROM mysql.user WHERE user='dstreambolt';

-- Should show: dstreambolt | %
```

## 📊 Dashboard Panels

### Panel 1: Ingestion Requests Per Minute
Shows real-time incoming request rate

### Panel 2: Success vs Failed (Pie Chart)
Visual breakdown of successful vs failed ingestion

### Panel 3: Processing Time
Average and max processing time for bundles

### Panel 4-5: Kafka Stats
Records written and failed counts

### Panel 6: Failed Bundles Table
Recent failed bundles with error details

### Panel 7: Consumer Lag
Kafka consumer lag by topic (important for monitoring backlog)

### Panel 8: Kafka Topics
Topic configuration and health

### Panel 9: Real-Time Metrics
Live counter values from ingestion_realtime_metrics table

### Panel 10: Processing Breakdown
Decompression vs Kafka write time

### Panel 11: Valid vs Invalid Lines
Line processing quality metrics

### Panel 12-13: Spark Metrics
Processing and failure metrics (when Spark jobs run)

## 🎯 Quick Fix Commands

```bash
# 1. Ensure tables exist
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/observability
./setup_observability.sh

# 2. Copy new dashboard
scp -i ~/dstreambolt-access-key.pem \
  grafana/devops-dashboard.json \
  ubuntu@13.232.132.240:/tmp/

# 3. Access Grafana
open http://13.232.132.240:3000

# 4. Import dashboard via UI
# Dashboards → Import → Upload devops-dashboard.json

# 5. Verify data
mysql -h 10.0.1.61 -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics << EOF
SELECT 'Ingestion Requests:', COUNT(*) FROM ingestion_requests;
SELECT 'Kafka Metrics:', COUNT(*) FROM kafka_topic_metrics;
SELECT 'Real-time Metrics:', metric_name, metric_value FROM ingestion_realtime_metrics;
EOF
```

## 📝 Next Steps

1. ✅ Import new dashboard
2. ⏳ Send test data to ingestion API
3. ⏳ Verify metrics appear in dashboard
4. ⏳ Set up alerts for critical metrics
5. ⏳ Add Spark processing metrics (when jobs run)

---

**Dashboard URL:** http://13.232.132.240:3000/d/devops-dashboard

**Need help?** Check `observability/QUICK_START.md` for verification queries.

