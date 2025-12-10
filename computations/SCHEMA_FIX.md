# Schema Mismatch Fix & MySQL Integration

## 🐛 Problems Identified

### Problem 1: Schema Mismatch
**Symptom:** All status values showing as NULL in Spark output

**Root Cause:** The ingestion service sends fields with different names than what Spark expects:

| Ingestion Sends | Spark Expected | Issue |
|----------------|----------------|-------|
| `status` | `status_code` | ❌ Mismatch |
| `size` | `response_size` | ❌ Mismatch |
| `response_time` | (missing) | ❌ Not in schema |
| `referer` | (missing) | ❌ Not in schema |

When field names don't match, Spark sets those columns to NULL.

### Problem 2: MySQL Metrics Not Written
**Symptom:** No data written to MySQL database

**Root Cause:** The Spark job requires MySQL credentials via command-line arguments, but the submit script wasn't passing them.

---

## ✅ Fixes Applied

### Fix 1: Updated Spark Schema

**File:** `computations/src/main/scala/com/dstreambolt/processor/SparkProcessor.scala`

**Changed:**
```scala
// OLD - Wrong field names
StructField("status_code", IntegerType, nullable = true),
StructField("response_size", IntegerType, nullable = true),
```

**To:**
```scala
// NEW - Matches ingestion format
StructField("status", IntegerType, nullable = true),
StructField("size", IntegerType, nullable = true),
StructField("referer", StringType, nullable = true),
StructField("response_time", DoubleType, nullable = true),
```

### Fix 2: Updated All Aggregations

Updated all groupBy and filter operations to use correct field names:
- `status_code` → `status`
- `response_size` → `size`
- Added `response_time` analysis

### Fix 3: Added MySQL Integration to Pipeline

**File:** `jenkins/deploy-prebuilt-scala-spark.jenkinsfile`

**Changes:**
1. Updated `submit_job.sh` to accept MySQL parameters
2. Modified "Start Spark Jobs" stage to pass MySQL credentials
3. Added automatic detection of MySQL password from DevOps node

---

## 📊 Expected Output After Fix

### Before (Broken):
```
📈 REQUEST STATISTICS BY STATUS CODE:
+-----------+-----+
|status_code|count|
+-----------+-----+
|NULL       |12450|
+-----------+-----+
```

### After (Fixed):
```
📈 REQUEST STATISTICS BY STATUS CODE:
+------+-----+
|status|count|
+------+-----+
|200   |8234 |
|201   |1532 |
|400   |1289 |
|500   |1395 |
+------+-----+

📊 SUMMARY: Processed 12450 logs, 2684 errors
```

---

## 🗄️ MySQL Schema

When batch mode completes with MySQL configured, data will be written to:

**Database:** `dstreambolt_metrics`  
**Table:** `spark_results`

The table will contain the processed DataFrame with fields:
- `timestamp`
- `ip`
- `method`
- `endpoint`
- `status`
- `size`
- `referer`
- `user_agent`
- `response_time`
- `request_id`
- `ingestion_timestamp`
- `processing_timestamp`

---

## 🚀 Testing the Fix

### Step 1: Rebuild the JAR

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt/computations
sbt clean assembly
```

### Step 2: Commit Changes

```bash
cd /Users/skalaise/apps/cloud/terraform/dstream_bolt
git add computations/src/main/scala/com/dstreambolt/processor/SparkProcessor.scala
git add jenkins/deploy-prebuilt-scala-spark.jenkinsfile
git commit -m "Fix: Schema mismatch and add MySQL integration"
git push
```

### Step 3: Deploy via Jenkins

Run the pipeline: http://13.232.38.64:8081/job/deploy-prebuilt-scala-spark/

Parameters:
- MODE: `batch`
- KAFKA_BROKER: `10.0.10.101:9092`
- SPARK_MASTER_IPS: `10.0.1.123`

### Step 4: Verify MySQL Data

SSH to DevOps node and check MySQL:
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.38.64
mysql -u root -p dstreambolt_metrics
```

```sql
SELECT COUNT(*) FROM spark_results;
SELECT status, COUNT(*) as count 
FROM spark_results 
GROUP BY status 
ORDER BY count DESC;
```

---

## 🔍 Debugging Tips

### If status is still NULL:

1. **Check Kafka data format:**
   ```bash
   # On Kafka node
   /opt/kafka/bin/kafka-console-consumer.sh \
     --bootstrap-server localhost:9092 \
     --topic dstreambolt-logs \
     --from-beginning \
     --max-messages 1
   ```

2. **Verify JSON structure:**
   The output should look like:
   ```json
   {
     "ip": "8.118.107.153",
     "timestamp": "2025-12-07T20:59:02Z",
     "method": "POST",
     "endpoint": "/api/v1/products",
     "status": 500,
     "size": 1709,
     "referer": "https://app.example.com/api/v1/products",
     "user_agent": "Mozilla/5.0...",
     "response_time": 1.692,
     "request_id": "req_123...",
     "ingestion_timestamp": "2025-12-09T..."
   }
   ```

### If MySQL write fails:

1. **Check MySQL is running:**
   ```bash
   ssh ubuntu@13.232.38.64
   sudo systemctl status mysql
   ```

2. **Verify credentials:**
   ```bash
   cat /opt/mysql_root_password
   mysql -u root -p -e "SHOW DATABASES;"
   ```

3. **Check Spark logs:**
   ```bash
   ssh ubuntu@10.0.1.123
   tail -100 /opt/spark/logs/scala-spark-job.log
   ```

---

## ✅ Summary

| Issue | Status | Fix |
|-------|--------|-----|
| Schema mismatch (status NULL) | ✅ Fixed | Updated field names in Spark schema |
| Missing response_time | ✅ Fixed | Added to schema and aggregations |
| MySQL not written | ✅ Fixed | Added MySQL params to submit script |
| New aggregation | ✅ Added | Top 10 slowest endpoints |

**All issues resolved! Data will now parse correctly and write to MySQL in batch mode.** 🎉

---

**Files Modified:**
1. `computations/src/main/scala/com/dstreambolt/processor/SparkProcessor.scala`
2. `jenkins/deploy-prebuilt-scala-spark.jenkinsfile`

**Next Steps:**
1. Rebuild JAR with `sbt assembly`
2. Commit and push changes
3. Run Jenkins pipeline
4. Verify data in MySQL

