# DStreamBolt Ingestion Service

Flask-based lightweight ingestion service for receiving gzipped log bundles, processing them, and sending to Kafka.

## Features

- ✅ Accepts POST requests with gzipped bundles (up to 10 MB)
- ✅ Returns `201 Accepted` immediately
- ✅ Writes metrics to MySQL database
- ✅ Tracks bundle status (incoming requests, failures)
- ✅ Unzips bundles and writes logs to Kafka
- ✅ Health check endpoint

## Installation

### Requirements

- Python 3.8+
- MySQL database
- Apache Kafka

### Install Dependencies

```bash
pip install -r requirements.txt
```

## Configuration

Set environment variables:

```bash
export MYSQL_HOST=localhost
export MYSQL_USER=root
export MYSQL_PASSWORD=your_password
export MYSQL_DB=dstreambolt_metrics
export KAFKA_BROKER=localhost:9092
export KAFKA_TOPIC=dstreambolt-logs
export PORT=5000
```

## Running

### Development Mode

```bash
python app.py
```

### Production Mode (with Gunicorn)

```bash
gunicorn -w 4 -b 0.0.0.0:5000 app:app
```

### Using Systemd Service

The service is automatically installed on the ingestion instance via Terraform.

```bash
sudo systemctl status ingest-api
sudo systemctl restart ingest-api
sudo journalctl -u ingest-api -f
```

## API Endpoints

### Health Check

```bash
GET /health
```

**Response:**
```json
{
  "status": "healthy",
  "service": "ingestion-api",
  "version": "1.0.0",
  "kafka": "connected",
  "timestamp": 1733395845.123
}
```

### Ingest Logs

```bash
POST /ingest
Content-Type: application/gzip
Content-Encoding: gzip
X-Request-ID: optional-request-id

[gzipped JSON payload]
```

**Request Body Format (before gzip):**
```json
[
  {
    "timestamp": "2025-12-05T10:30:45Z",
    "ip": "192.168.1.100",
    "method": "GET",
    "endpoint": "/api/v1/users",
    "status_code": 200,
    "response_size": 1234
  }
]
```

**Response (201 Accepted):**
```json
{
  "status": "accepted",
  "request_id": "req_1733395845123",
  "logs_count": 100,
  "processing_time_ms": 45
}
```

**Error Response (400/500):**
```json
{
  "error": "Failed to decompress: not in gzip format"
}
```

## Database Schema

### ingestion_metrics Table

Stores detailed metrics for each ingestion request:

```sql
CREATE TABLE ingestion_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    request_id VARCHAR(255),
    bundle_size_bytes INT,
    uncompressed_size_bytes INT,
    status VARCHAR(50),
    processing_time_ms INT,
    kafka_topic VARCHAR(255),
    error_message TEXT,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(status)
);
```

### bundle_status Table

Tracks bundle processing status:

```sql
CREATE TABLE bundle_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) UNIQUE,
    status VARCHAR(50),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX(request_id),
    INDEX(status)
);
```

## Monitoring

### Query Metrics

```sql
-- Recent ingestion activity
SELECT * FROM ingestion_metrics 
ORDER BY timestamp DESC 
LIMIT 10;

-- Success rate
SELECT 
    status, 
    COUNT(*) as count,
    ROUND(AVG(processing_time_ms), 2) as avg_time_ms,
    ROUND(AVG(bundle_size_bytes)/1024, 2) as avg_size_kb
FROM ingestion_metrics
WHERE timestamp > NOW() - INTERVAL 1 HOUR
GROUP BY status;

-- Failed requests
SELECT * FROM ingestion_metrics
WHERE status != 'success'
ORDER BY timestamp DESC
LIMIT 20;
```

### View Logs

```bash
# Systemd logs
sudo journalctl -u ingest-api -f

# Application logs
tail -f /var/log/ingest-api.log
```

## Testing

### Send Test Bundle

```bash
# Generate test log
echo '{"timestamp":"2025-12-05T10:30:45Z","ip":"192.168.1.100","method":"GET","endpoint":"/api/v1/users","status_code":200}' > test.json

# Gzip it
gzip test.json

# Send to ingestion service
curl -X POST \
  -H "Content-Type: application/gzip" \
  -H "Content-Encoding: gzip" \
  --data-binary @test.json.gz \
  http://localhost:5000/ingest
```

### Using Python Script

```bash
cd ../examples
python 02-send-to-ingest.py \
  --alb-url http://localhost:5000 \
  --file test.log
```

## Error Handling

The service handles various error scenarios:

- **Decompression errors**: Returns 400 with error message
- **JSON parsing errors**: Returns 400 with error message
- **Kafka connection errors**: Returns 500, logs error to MySQL
- **Database errors**: Continues processing, logs warning

## Performance

- **Max bundle size**: 10 MB (configurable)
- **Concurrent requests**: Handled by Gunicorn workers (4 default)
- **Processing time**: ~50ms average for 1000 log entries
- **Throughput**: ~200 requests/second on t3.micro

## Security

- Deployed behind Application Load Balancer with mTLS
- SSL/TLS certificates managed by Terraform
- AWS Secrets Manager for sensitive configuration
- VPC security groups restrict access

## Architecture

```
Internet → ALB (mTLS) → Ingestion Service → Kafka
                              ↓
                           MySQL (metrics)
```

## Troubleshooting

### Service Not Starting

```bash
# Check service status
sudo systemctl status ingest-api

# Check logs for errors
sudo journalctl -u ingest-api -n 50

# Verify Python dependencies
source /opt/dstreambolt/agent/venv/bin/activate
pip list
```

### Kafka Connection Issues

```bash
# Test Kafka connectivity
telnet <kafka-broker-ip> 9092

# Check Kafka broker status
# (on kafka instance)
/opt/kafka/bin/kafka-broker-api-versions.sh \
  --bootstrap-server localhost:9092
```

### Database Connection Issues

```bash
# Test MySQL connection
mysql -h <mysql-host> -u root -p

# Check if database exists
mysql -h <mysql-host> -u root -p -e "SHOW DATABASES;"
```

## Development

### Local Setup

```bash
# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export MYSQL_HOST=localhost
export MYSQL_PASSWORD=test123
export KAFKA_BROKER=localhost:9092

# Run in debug mode
export DEBUG=true
python app.py
```

### Run Tests

```bash
pytest tests/
```

## Production Deployment

The service is automatically deployed via Terraform to AWS EC2 instances.

See `../terraform/modules/ingest/` for infrastructure configuration.

## License

Part of DStreamBolt Platform

