# Grafana Dashboard Setup Guide for DStreamBolt

## Prerequisites
- Grafana is installed on DevOps node (13.232.132.240)
- MySQL datasource needs to be configured
- Dashboard JSON file is ready

## Step 1: Access Grafana

```bash
# Grafana is accessible at:
http://13.232.132.240:3000

# Default credentials:
Username: admin
Password: DStreamBolt2025!
```

## Step 2: Add MySQL Data Source

### Option A: Via Grafana UI

1. Open Grafana: `http://13.232.132.240:3000`
2. Login with credentials above
3. Go to **Configuration** → **Data Sources** (gear icon on left)
4. Click **Add data source**
5. Select **MySQL**
6. Configure:
   ```
   Name: DStreamBolt-MySQL
   Host: localhost:3306
   Database: dstreambolt_metrics
   User: dstreambolt
   Password: DStreamBolt2025!
   ```
7. Click **Save & Test**

### Option B: Via API (Automated)

Run this command from your local machine:

```bash
curl -X POST http://13.232.132.240:3000/api/datasources \
  -H "Content-Type: application/json" \
  -u admin:DStreamBolt2025! \
  -d '{
    "name": "DStreamBolt-MySQL",
    "type": "mysql",
    "url": "localhost:3306",
    "database": "dstreambolt_metrics",
    "user": "dstreambolt",
    "secureJsonData": {
      "password": "DStreamBolt2025!"
    },
    "access": "proxy",
    "isDefault": true
  }'
```

## Step 3: Import Dashboard

### Option A: Via Grafana UI

1. Go to **Dashboards** → **Import** (+ icon on left)
2. Click **Upload JSON file**
3. Select `grafana/dstreambolt-dashboard.json`
4. Select datasource: **DStreamBolt-MySQL**
5. Click **Import**

### Option B: Via API (Automated)

```bash
# From the dstream_bolt directory
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt

curl -X POST http://13.232.132.240:3000/api/dashboards/db \
  -H "Content-Type: application/json" \
  -u admin:DStreamBolt2025! \
  -d @grafana/dstreambolt-dashboard.json
```

### Option C: Automated Script

Run the provided setup script:

```bash
cd terraform
./setup_grafana_dashboard.sh
```

## Step 4: Verify Dashboard

1. Go to **Dashboards** → **Browse**
2. Find **DStreamBolt Real-Time Analytics**
3. Click to open

You should see:
- **Requests Per Minute**: Line chart of total requests
- **Error Rate**: Percentage of errors over time
- **Status Code Distribution**: Pie chart of HTTP status codes
- **Average Response Time**: Gauge showing current avg response time
- **Current Requests/sec**: Real-time RPS metric
- **Top 10 Slowest Endpoints**: Table with performance metrics
- **Top 10 Most Requested Endpoints**: Bar chart
- **Response Time Percentiles**: Line chart with avg, p95, p99
- **Error Analysis**: Table showing all errors

## Dashboard Features

### Time Range
- Default: Last 1 hour
- Can be changed using time picker (top right)
- Supports: 5m, 15m, 1h, 6h, 24h, 7d, 30d

### Refresh Rate
- Auto-refresh: Every 10 seconds
- Can be changed in dashboard settings

### Variables (Optional Enhancement)

Add these template variables for filtering:
1. **Endpoint**: `SELECT DISTINCT endpoint FROM endpoint_summary`
2. **Status**: `SELECT DISTINCT status FROM status_summary`
3. **Method**: `SELECT DISTINCT method FROM endpoint_summary`

## Troubleshooting

### No Data Showing

1. **Check if streaming job is running:**
   ```bash
   ssh ubuntu@15.206.123.221  # Spark Master
   ps aux | grep SparkProcessor
   ```

2. **Check if data exists in MySQL:**
   ```bash
   ssh ubuntu@13.232.132.240
   mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics
   SELECT COUNT(*) FROM status_summary;
   SELECT COUNT(*) FROM endpoint_summary;
   ```

3. **Check Grafana datasource connection:**
   - Go to Data Sources → DStreamBolt-MySQL
   - Click **Save & Test**
   - Should show: "Database Connection OK"

### Dashboard Shows Errors

1. **Check MySQL permissions:**
   ```sql
   SHOW GRANTS FOR 'dstreambolt'@'%';
   ```

2. **Verify table structure:**
   ```sql
   DESCRIBE status_summary;
   DESCRIBE endpoint_summary;
   ```

3. **Check Grafana logs:**
   ```bash
   ssh ubuntu@13.232.132.240
   sudo journalctl -u grafana-server -f
   ```

## Creating Custom Panels

### Example: Add "Top Error Endpoints" Panel

1. Click **Add Panel** (top right)
2. Select **Table** visualization
3. Query:
   ```sql
   SELECT 
     endpoint,
     method,
     SUM(error_count) as total_errors,
     ROUND(AVG(avg_response_time), 3) as avg_response_time
   FROM endpoint_summary 
   WHERE error_count > 0 
     AND window_start >= NOW() - INTERVAL 1 HOUR
   GROUP BY endpoint, method 
   ORDER BY total_errors DESC 
   LIMIT 10
   ```
4. Configure columns and formatting
5. Save panel

### Example: Add "Unique IPs Over Time" Panel

1. Add Panel → Time series
2. Query:
   ```sql
   SELECT 
     window_start as time,
     SUM(unique_ips) as value
   FROM endpoint_summary 
   WHERE window_start >= $__timeFrom()
     AND window_start <= $__timeTo()
   GROUP BY window_start 
   ORDER BY window_start
   ```
3. Configure axis labels and legend
4. Save panel

## Advanced Queries

### Request Rate by Endpoint
```sql
SELECT 
  window_start as time,
  endpoint as metric,
  SUM(request_count) as value
FROM endpoint_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start, endpoint 
ORDER BY window_start
```

### Error Rate by Status Code
```sql
SELECT 
  window_start as time,
  CONCAT('Status ', status) as metric,
  SUM(request_count) as value
FROM status_summary 
WHERE status >= 400 
  AND window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start, status 
ORDER BY window_start
```

### Response Time Heatmap
```sql
SELECT 
  UNIX_TIMESTAMP(window_start) as time,
  endpoint as metric,
  AVG(avg_response_time) as value
FROM endpoint_summary 
WHERE window_start >= NOW() - INTERVAL 1 HOUR
GROUP BY window_start, endpoint 
ORDER BY time
```

## Alerting (Optional)

### Configure Alert: High Error Rate

1. Edit "Error Rate" panel
2. Go to **Alert** tab
3. Create alert rule:
   - Condition: `WHEN last() OF query(A) IS ABOVE 10`
   - Evaluate every: `1m`
   - For: `5m`
4. Add notification channel (Email, Slack, etc.)

### Configure Alert: Slow Response Time

1. Edit "Average Response Time" panel
2. Create alert rule:
   - Condition: `WHEN last() OF query(A) IS ABOVE 2`
   - Evaluate every: `1m`
   - For: `5m`

## Dashboard URL

Once imported, dashboard will be available at:
```
http://13.232.132.240:3000/d/dstreambolt-analytics/dstreambolt-real-time-analytics
```

## Next Steps

1. ✅ Import dashboard using steps above
2. ✅ Start streaming Spark job with `--mode streaming`
3. ✅ Watch data flow into Grafana in real-time
4. 🎨 Customize colors, thresholds, and layouts
5. 📊 Add custom panels for specific use cases
6. 🚨 Set up alerting rules
7. 📱 Configure notification channels

## Support

For issues or questions:
1. Check Grafana logs: `sudo journalctl -u grafana-server -f`
2. Check MySQL connectivity from Grafana UI
3. Verify data exists in MySQL tables
4. Ensure streaming Spark job is running

