# DStreamBolt Setup Scripts

Complete modular setup scripts for DStreamBolt infrastructure components.

## 📁 Directory Structure

```
setup_scripts/
├── setup_all.sh           # Master orchestrator script
├── setup_jenkins.sh       # Jenkins CI/CD setup
├── setup_grafana.sh       # Grafana monitoring setup
├── setup_mysql.sh         # MySQL database setup
├── setup_kafka.sh         # Kafka broker + Zookeeper setup
├── setup_spark_master.sh  # Spark Master setup
├── setup_spark_worker.sh  # Spark Worker/Executor setup
├── setup_ingestion.sh     # Ingestion API service setup
└── setup_akhq.sh          # AKHQ (Kafka UI) setup
```

## 🚀 Quick Start

### One-Click Complete Setup

Run the master script with sudo:

```bash
sudo ./setup_all.sh
```

This will:
1. Show an interactive menu
2. Let you select components to install
3. Auto-detect configuration from Terraform
4. Install and configure selected services
5. Provide access information

### Individual Component Setup

Each script can be run independently:

```bash
# Jenkins
sudo ./setup_jenkins.sh

# Grafana
sudo MYSQL_PASSWORD="YourPassword" ./setup_grafana.sh

# MySQL
sudo MYSQL_ROOT_PASSWORD="YourPassword" ./setup_mysql.sh

# Kafka
sudo ./setup_kafka.sh

# Spark Master
sudo ./setup_spark_master.sh

# Spark Worker
sudo SPARK_MASTER_HOST="10.0.1.123" ./setup_spark_worker.sh

# Ingestion
sudo KAFKA_BROKER="10.0.10.248:9092" MYSQL_HOST="10.0.1.61" ./setup_ingestion.sh

# AKHQ
sudo KAFKA_BROKER="10.0.10.248:9092" ./setup_akhq.sh
```

## 📋 Setup Order Recommendation

For complete infrastructure, install in this order:

1. **DevOps Node:**
   ```bash
   sudo ./setup_mysql.sh
   sudo ./setup_jenkins.sh
   sudo ./setup_grafana.sh
   sudo ./setup_akhq.sh
   ```

2. **Kafka Node:**
   ```bash
   sudo ./setup_kafka.sh
   ```

3. **Spark Master Node:**
   ```bash
   sudo ./setup_spark_master.sh
   ```

4. **Spark Executor Node:**
   ```bash
   sudo SPARK_MASTER_HOST="<master-ip>" ./setup_spark_worker.sh
   ```

5. **Ingestion Node:**
   ```bash
   sudo KAFKA_BROKER="<kafka-ip>:9092" \
        MYSQL_HOST="<mysql-ip>" \
        MYSQL_PASSWORD="<password>" \
        ./setup_ingestion.sh
   ```

## 🔧 Configuration

### Environment Variables

Each script accepts configuration via environment variables:

| Script | Variables | Description |
|--------|-----------|-------------|
| `setup_mysql.sh` | `MYSQL_ROOT_PASSWORD` | MySQL root password (default: DStreamBolt2025!) |
| `setup_grafana.sh` | `GRAFANA_ADMIN_PASSWORD`, `MYSQL_HOST`, `MYSQL_PASSWORD` | Grafana admin password and MySQL connection |
| `setup_kafka.sh` | `KAFKA_VERSION` | Kafka version to install (default: 3.8.1) |
| `setup_spark_master.sh` | `SPARK_VERSION` | Spark version (default: 3.5.0) |
| `setup_spark_worker.sh` | `SPARK_MASTER_HOST` | Spark master IP address |
| `setup_ingestion.sh` | `KAFKA_BROKER`, `MYSQL_HOST`, `MYSQL_PASSWORD` | Kafka and MySQL connection details |
| `setup_akhq.sh` | `KAFKA_BROKER`, `ADMIN_USERNAME`, `ADMIN_PASSWORD` | Kafka connection and AKHQ credentials |

### Interactive Prompts

If required variables are not set, scripts will prompt interactively.

## 📊 Service Verification

After setup, verify services are running:

```bash
# Check all services
systemctl status jenkins grafana-server mysql kafka zookeeper spark-master spark-worker dstreambolt-ingest akhq

# Check specific service
systemctl status jenkins

# View logs
journalctl -u jenkins -f
```

## 🔍 Features

### ✅ Idempotent
- Safe to run multiple times
- Detects existing installations
- Prompts before overwriting

### ✅ Comprehensive Logging
- Each script logs to `/var/log/<component>-setup.log`
- Master script creates consolidated log in `/var/log/dstreambolt-setup/`

### ✅ Self-Contained
- All dependencies installed automatically
- No manual pre-configuration needed
- Works on clean Ubuntu 22.04 systems

### ✅ Production-Ready
- Systemd service files
- Automatic startup on boot
- Proper user permissions
- Security configurations

## 📝 What Each Script Does

### setup_jenkins.sh
- Installs Java 17
- Installs Jenkins
- Configures port 8080
- Generates SSH key for GitHub
- Installs recommended plugins
- Outputs initial admin password

### setup_grafana.sh
- Installs Grafana
- Configures for /grafana subpath
- Sets admin password
- Configures MySQL datasource
- Imports dashboards (if available)

### setup_mysql.sh
- Installs MySQL Server
- Sets root password
- Creates `dstreambolt_metrics` database
- Creates all required tables
- Creates remote access user `dstreambolt`
- Configures for remote connections

### setup_kafka.sh
- Installs Java 11
- Downloads and installs Kafka
- Configures Zookeeper
- Configures Kafka broker
- Creates systemd services
- Creates default topics:
  - `dstreambolt-logs` (3 partitions)
  - `dstreambolt-metrics` (1 partition)

### setup_spark_master.sh
- Installs Java 11
- Downloads and installs Spark
- Configures Spark Master
- Creates systemd service
- Starts on port 7077
- Web UI on port 8080

### setup_spark_worker.sh
- Installs Java 11
- Downloads and installs Spark
- Connects to specified master
- Configures worker
- Creates systemd service
- Web UI on port 8081

### setup_ingestion.sh
- Installs Python 3 and virtualenv
- Copies application code
- Installs Python dependencies
- Configures environment
- Creates systemd service
- Starts Gunicorn on port 5000

### setup_akhq.sh
- Installs Java 17
- Downloads AKHQ
- Configures Kafka connection
- Sets up authentication
- Creates systemd service
- Starts on port 8081 at /kafkamgr

## 🔐 Default Credentials

| Service | Username | Password | Notes |
|---------|----------|----------|-------|
| Jenkins | admin | *See output or `/tmp/jenkins_initial_password.txt`* | Change on first login |
| Grafana | admin | DStreamBolt2025! | Can be overridden |
| MySQL | root | DStreamBolt2025! | Can be overridden |
| MySQL | dstreambolt | DStreamBolt2025! | For application access |
| AKHQ | admin | DStreamBolt2025! | Full access |
| AKHQ | user | user123 | Read-only |

## 🌐 Access URLs

After setup, access services at:

| Service | URL | Port |
|---------|-----|------|
| Jenkins | `http://<ip>:8080` | 8080 |
| Grafana | `http://<ip>:3000/grafana` | 3000 |
| AKHQ | `http://<ip>:8081/kafkamgr` | 8081 |
| Spark Master UI | `http://<ip>:8080` | 8080 |
| Spark Worker UI | `http://<ip>:8081` | 8081 |
| Ingestion Health | `http://<ip>:5000/health` | 5000 |
| Ingestion API | `http://<ip>:5000/ingest` | 5000 |
| MySQL | `mysql -h <ip> -u root -p` | 3306 |
| Kafka | `<ip>:9092` | 9092 |

## 🛠️ Troubleshooting

### Service won't start

```bash
# Check service status
systemctl status <service-name>

# Check logs
journalctl -u <service-name> -n 100 --no-pager

# Check setup log
cat /var/log/<component>-setup.log
```

### Re-run setup

Each script asks before reinstalling. Answer 'y' to proceed or 'n' to skip.

### Reset service

```bash
# Stop service
sudo systemctl stop <service-name>

# Remove service file
sudo rm /etc/systemd/system/<service-name>.service

# Reload systemd
sudo systemctl daemon-reload

# Re-run setup script
sudo ./setup_<component>.sh
```

### Check connectivity

```bash
# Test MySQL connection
mysql -h <host> -u dstreambolt -p'DStreamBolt2025!' dstreambolt_metrics

# Test Kafka connection
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server <host>:9092

# Test Ingestion API
curl http://<host>:5000/health
```

## 📚 Additional Resources

- Individual setup logs: `/var/log/*-setup.log`
- Master setup log: `/var/log/dstreambolt-setup/master_setup_*.log`
- Service logs: `journalctl -u <service-name>`

## 🔄 Updates

To update a component:

1. Stop the service: `sudo systemctl stop <service>`
2. Run the setup script again: `sudo ./setup_<component>.sh`
3. Answer 'y' when prompted to reinstall

## 💡 Tips

1. **Always run with sudo** - Scripts need root access
2. **Check logs** - Each script produces detailed logs
3. **Use environment variables** - Avoid interactive prompts in automation
4. **Verify after setup** - Check service status and test connectivity
5. **Backup before reinstall** - Scripts will ask before overwriting

## 📧 Support

For issues or questions, check:
- Setup logs in `/var/log/`
- Service logs via `journalctl`
- Individual script documentation (comments in each file)

