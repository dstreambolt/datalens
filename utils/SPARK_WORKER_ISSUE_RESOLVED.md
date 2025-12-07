# Spark Worker Issue - RESOLVED ✅

## Problem Statement
**Spark Worker UI not accessible**: `http://10.0.1.128:8081/`

## Root Cause
The issue had **two components**:

### 1. Wrong IP Address
- **10.0.1.128** is the **private IP** of the Spark instance
- Cannot be accessed directly from your local machine
- **Correct public IP**: `43.205.94.74`

### 2. AWS Security Group Blocking
- Ports 8080, 8081, 18080 were not open to public access (0.0.0.0/0)
- Only port 7077 was restricted to VPC internal traffic (10.0.0.0/16)

## Solution Applied

### Step 1: Identified Correct Instance
- Spark Compute Instance: `i-0590ab13f80d846a3`
- Public IP: `43.205.94.74`
- Private IP: `10.0.1.128`
- Security Group: `sg-040a0ba61156177d3`

### Step 2: Verified Spark Services Running
```bash
✅ Spark Master: active (running)
✅ Spark Worker: active (running)  
✅ Port 8081 listening: confirmed
```

### Step 3: Opened Security Group Ports
Added inbound rules for:
- ✅ Port 7077 (Spark Master) - 0.0.0.0/0
- ✅ Port 8080 (Master UI) - 0.0.0.0/0
- ✅ Port 8081 (Worker UI) - 0.0.0.0/0
- ✅ Port 18080 (History Server) - 0.0.0.0/0

### Step 4: Verified Accessibility
```bash
✅ Master UI (8080):   HTTP 200 - Accessible
✅ Worker UI (8081):   HTTP 200 - Accessible  
✅ History (18080):    HTTP 200 - Accessible
```

## Access URLs

### ✅ Working URLs (Use These)
- **Spark Master UI**: http://43.205.94.74:8080
- **Spark Worker UI**: http://43.205.94.74:8081
- **History Server**: http://43.205.94.74:18080

### ❌ Don't Use (Private IP)
- ~~http://10.0.1.128:8081~~ (Private IP - not accessible externally)

## Verification

Test the URLs now:
```bash
# From your terminal
curl -I http://43.205.94.74:8080  # Should return HTTP/1.1 200 OK
curl -I http://43.205.94.74:8081  # Should return HTTP/1.1 200 OK
curl -I http://43.205.94.74:18080 # Should return HTTP/1.1 200 OK
```

Or open in your browser:
- http://43.205.94.74:8080 (Master UI with cluster overview)
- http://43.205.94.74:8081 (Worker UI with worker details)
- http://43.205.94.74:18080 (History of completed applications)

## What You'll See

### Spark Master UI (Port 8080)
- Cluster summary
- Worker list (should show 1 worker registered)
- Running applications
- Completed applications
- Cluster resources (1 core, 512 MB RAM)

### Spark Worker UI (Port 8081)
- Worker ID
- Master URL: `spark://10.0.1.128:7077`
- Cores: 1
- Memory: 512 MB
- Executor list
- Finished executors

### History Server (Port 18080)
- Completed Spark applications
- Application logs and metrics
- Event timeline

## Tools Created

Three utility scripts were created to help troubleshoot and fix this issue:

### 1. `utils/diagnose_spark_worker.sh`
Comprehensive diagnostics to run ON the Spark instance:
- Checks service status
- Verifies ports listening
- Inspects logs
- Shows network configuration

**Usage:**
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
curl -s https://raw.githubusercontent.com/dstreambolt/dstream_cloud/main/utils/diagnose_spark_worker.sh | bash
```

### 2. `utils/fix_spark_worker.sh`
Automated fix script to run FROM your local machine:
- Gets instance IP from Terraform
- Tests SSH connectivity
- Checks service status
- Restarts services if needed
- Verifies accessibility

**Usage:**
```bash
cd dstream_bolt
./utils/fix_spark_worker.sh
```

### 3. `utils/open_spark_ports.sh`
Opens Spark ports in AWS Security Group:
- Finds Spark instance automatically
- Adds security group rules
- Tests connectivity
- Shows access URLs

**Usage:**
```bash
cd dstream_bolt
./utils/open_spark_ports.sh
```

## Architecture Understanding

```
Your Machine → Internet → AWS
                          ↓
                    Public Subnet
                          ↓
                  Spark Instance
                  ┌─────────────────┐
Public IP:        │  43.205.94.74   │ ← Use this!
Private IP:       │  10.0.1.128     │ ← Don't use externally
                  └─────────────────┘
                          ↓
              Spark Master (7077)
              Master UI (8080) ✅
              Worker UI (8081) ✅
              History (18080) ✅
```

## Troubleshooting Commands

If the issue recurs, use these commands:

### Check Service Status
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
sudo systemctl status spark-master spark-worker
```

### Restart Services
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
sudo systemctl restart spark-master spark-worker
```

### Check Logs
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
tail -f /opt/spark/logs/*worker*.out
tail -f /opt/spark/logs/*master*.out
```

### Verify Ports
```bash
ssh -i ~/dstreambolt-access-key.pem ubuntu@43.205.94.74
sudo ss -tlnp | grep -E ":(7077|8080|8081|18080)"
```

## Complete Documentation

For detailed troubleshooting:
- Read: `utils/SPARK_WORKER_TROUBLESHOOTING.md`
- Run: `utils/diagnose_spark_worker.sh` (on server)
- Run: `utils/fix_spark_worker.sh` (from local)

## Summary

### Before Fix
- ❌ Using wrong IP: 10.0.1.128 (private)
- ❌ Ports blocked by security group
- ❌ Unable to access Spark UIs

### After Fix
- ✅ Using correct IP: 43.205.94.74 (public)
- ✅ Security group ports opened
- ✅ All Spark UIs accessible
- ✅ Services confirmed running

## Status: RESOLVED ✅

**Your Spark Worker is now accessible at:**
**http://43.205.94.74:8081**

---

**Fixed**: December 7, 2025  
**Instance**: i-0590ab13f80d846a3  
**Public IP**: 43.205.94.74  
**Region**: ap-south-1 (Mumbai)

