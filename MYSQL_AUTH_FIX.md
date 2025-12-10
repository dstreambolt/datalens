# MySQL Authentication Fix Guide

## 🐛 Problem

MySQL root user is configured with `auth_socket` plugin, which means:
- ✅ Root can only login via `sudo mysql` (no password)
- ❌ Cannot connect with password: `mysql -u root -p`
- ❌ Remote applications (Spark, Ingestion) cannot connect as root

**Verification:**
```bash
sudo mysql -e "SELECT user, host, plugin FROM mysql.user WHERE user='root';"
```
Output shows: `plugin = auth_socket`

## ✅ Solution

Create a new user `dstreambolt` with password authentication for application access.

### Step 1: Run the Fix Script

On the DevOps node:
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@13.232.132.240
bash fix_mysql_auth.sh
```

This script will:
1. ✅ Create `dstreambolt` user with password authentication
2. ✅ Grant full privileges on `dstreambolt_metrics` database
3. ✅ Create all required tables (ingestion_metrics, bundle_status, spark_results)
4. ✅ Configure MySQL to listen on all interfaces (0.0.0.0)
5. ✅ Restart MySQL service

### Step 2: Test Connection

```bash
# Local connection
mysql -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# Check tables
mysql -u dstreambolt -p'DStreamBolt2025!' -e "SHOW TABLES FROM dstreambolt_metrics;"
```

Expected output:
```
+--------------------------------+
| Tables_in_dstreambolt_metrics  |
+--------------------------------+
| bundle_status                  |
| ingestion_metrics              |
| spark_results                  |
+--------------------------------+
```

## 📋 Connection Details

| Field | Value |
|-------|-------|
| **Host** | 13.232.132.240 |
| **User** | `dstreambolt` |
| **Password** | `DStreamBolt2025!` |
| **Database** | `dstreambolt_metrics` |
| **Port** | 3306 (default) |

## 🔐 User Comparison

| User | Plugin | Privileges | Use Case |
|------|--------|-----------|----------|
| **root** | auth_socket | ALL | Admin tasks via `sudo mysql` |
| **dstreambolt** | mysql_native_password | ALL on dstreambolt_metrics.* | Application access |

## 📊 Database Schema

### Table: spark_results
Stores processed data from Spark jobs.

| Column | Type | Description |
|--------|------|-------------|
| id | INT AUTO_INCREMENT | Primary key |
| timestamp | VARCHAR(50) | Log timestamp |
| ip | VARCHAR(50) | Client IP |
| method | VARCHAR(10) | HTTP method |
| endpoint | VARCHAR(255) | API endpoint |
| status | INT | HTTP status code |
| size | INT | Response size |
| referer | TEXT | Referer URL |
| user_agent | TEXT | User agent string |
| response_time | DOUBLE | Response time in seconds |
| request_id | VARCHAR(255) | Request ID |
| ingestion_timestamp | VARCHAR(50) | When ingested |
| processing_timestamp | TIMESTAMP | When processed by Spark |

### Table: ingestion_metrics
Stores ingestion API metrics.

| Column | Type | Description |
|--------|------|-------------|
| id | INT AUTO_INCREMENT | Primary key |
| timestamp | TIMESTAMP | Metric timestamp |
| request_id | VARCHAR(255) | Request ID |
| bundle_size_bytes | INT | Compressed size |
| uncompressed_size_bytes | INT | Uncompressed size |
| status | VARCHAR(50) | Status (success/failed) |
| processing_time_ms | INT | Processing time |
| kafka_topic | VARCHAR(255) | Kafka topic |
| error_message | TEXT | Error if failed |

### Table: bundle_status
Tracks bundle processing status.

| Column | Type | Description |
|--------|------|-------------|
| id | INT AUTO_INCREMENT | Primary key |
| request_id | VARCHAR(255) UNIQUE | Request ID |
| status | VARCHAR(50) | Current status |
| created_at | TIMESTAMP | Created time |
| updated_at | TIMESTAMP | Last updated |

## 🔍 Useful Queries

### Check Spark Results Count
```bash
mysql -u dstreambolt -p'DStreamBolt2025!' -e "SELECT COUNT(*) FROM dstreambolt_metrics.spark_results;"
```

### View Recent Spark Results
```sql
SELECT 
    endpoint, 
    status, 
    COUNT(*) as count,
    AVG(response_time) as avg_response_time
FROM dstreambolt_metrics.spark_results
GROUP BY endpoint, status
ORDER BY count DESC
LIMIT 10;
```

### Check Ingestion Metrics
```sql
SELECT 
    status,
    COUNT(*) as count,
    AVG(processing_time_ms) as avg_processing_time,
    AVG(bundle_size_bytes) as avg_bundle_size
FROM dstreambolt_metrics.ingestion_metrics
WHERE timestamp > DATE_SUB(NOW(), INTERVAL 1 HOUR)
GROUP BY status;
```

### Check Bundle Status
```sql
SELECT 
    status, 
    COUNT(*) as count
FROM dstreambolt_metrics.bundle_status
GROUP BY status;
```

## 🚀 Application Configuration

### Ingestion Service
Uses environment variables (already configured):
```bash
MYSQL_HOST=13.232.132.240
MYSQL_USER=dstreambolt
MYSQL_PASSWORD=DStreamBolt2025!
MYSQL_DB=dstreambolt_metrics
```

### Spark Jobs
Receives credentials via command-line arguments (Jenkins pipeline updated):
```bash
--mysql-host 13.232.132.240
--mysql-user dstreambolt
--mysql-password DStreamBolt2025!
--mysql-database dstreambolt_metrics
--mysql-table spark_results
```

## 🔧 Troubleshooting

### Issue: "Access denied for user 'dstreambolt'"
**Solution:** Run the fix script again:
```bash
bash fix_mysql_auth.sh
```

### Issue: "Can't connect to MySQL server"
**Check MySQL is running:**
```bash
sudo systemctl status mysql
```

**Check MySQL is listening on all interfaces:**
```bash
sudo grep bind-address /etc/mysql/mysql.conf.d/mysqld.cnf
```
Should show: `bind-address = 0.0.0.0`

**Restart if needed:**
```bash
sudo systemctl restart mysql
```

### Issue: "Table doesn't exist"
**Create tables manually:**
```bash
sudo mysql dstreambolt_metrics < /tmp/create_tables.sql
```

Or run the fix script which creates tables automatically.

## 📝 Security Notes

1. **Password in Scripts**: The password `DStreamBolt2025!` is hardcoded for development/testing. For production:
   - Use environment variables
   - Use AWS Secrets Manager
   - Use IAM authentication

2. **Network Access**: MySQL is configured to listen on 0.0.0.0 but access is restricted by:
   - AWS Security Groups (only internal VPC traffic)
   - MySQL user grants (% wildcard only allows authenticated users)

3. **Root Access**: Root user remains secure with auth_socket (sudo only)

## ✅ Verification Checklist

- [ ] `dstreambolt` user can connect with password
- [ ] All three tables exist in `dstreambolt_metrics` database
- [ ] MySQL listens on 0.0.0.0 (check bind-address)
- [ ] MySQL service is running
- [ ] Jenkins pipeline updated to use `dstreambolt` user
- [ ] Ingestion service can write metrics
- [ ] Spark job can write results

## 📚 Quick Reference

**Helper Script:** `./MYSQL_CONNECTION.sh` - Shows all connection commands
**Fix Script:** `./fix_mysql_auth.sh` - Fixes authentication and creates user

---

**All authentication issues resolved! Applications can now connect to MySQL with the `dstreambolt` user.** 🎉

