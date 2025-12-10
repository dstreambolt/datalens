-- Complete Observability Schema for DStreamBolt
-- Run this to create all metrics tables across the pipeline

USE dstreambolt_metrics;

-- ============================================================================
-- INGESTION LAYER TABLES
-- ============================================================================

-- 1. Ingestion Requests (every incoming HTTP request)
CREATE TABLE IF NOT EXISTS ingestion_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    source_ip VARCHAR(45),
    user_agent VARCHAR(500),
    content_type VARCHAR(100),
    bundle_size_bytes INT,
    http_status INT,
    processing_stage VARCHAR(50),
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(http_status),
    INDEX(processing_stage)
) ENGINE=InnoDB COMMENT='Captures every incoming HTTP request';

-- 2. Bundle Processing (detailed processing metrics)
CREATE TABLE IF NOT EXISTS bundle_processing (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    bundle_size_bytes INT NOT NULL,
    uncompressed_size_bytes INT,
    decompression_time_ms INT,
    total_lines INT,
    valid_lines INT,
    invalid_lines INT,
    kafka_write_time_ms INT,
    total_processing_time_ms INT,
    status VARCHAR(50) NOT NULL,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(status)
) ENGINE=InnoDB COMMENT='Detailed bundle processing metrics';

-- 3. Kafka Production Metrics
CREATE TABLE IF NOT EXISTS kafka_production_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    topic VARCHAR(255) NOT NULL,
    records_attempted INT NOT NULL,
    records_successful INT NOT NULL,
    records_failed INT NOT NULL,
    write_time_ms INT,
    avg_record_size_bytes INT,
    kafka_errors TEXT,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(topic)
) ENGINE=InnoDB COMMENT='Kafka production success/failure tracking';

-- 4. Failed Bundles (comprehensive failure tracking)
CREATE TABLE IF NOT EXISTS failed_bundles (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    request_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP(3) DEFAULT CURRENT_TIMESTAMP(3),
    failure_stage VARCHAR(50) NOT NULL,
    error_type VARCHAR(100),
    error_message TEXT,
    bundle_size_bytes INT,
    source_ip VARCHAR(45),
    retry_count INT DEFAULT 0,
    bundle_data_sample TEXT,
    stack_trace TEXT,
    resolved BOOLEAN DEFAULT FALSE,
    resolved_at TIMESTAMP NULL,
    INDEX(request_id),
    INDEX(timestamp),
    INDEX(failure_stage),
    INDEX(resolved)
) ENGINE=InnoDB COMMENT='Failed bundles with full error context';

-- 5. Ingestion Real-time Metrics
CREATE TABLE IF NOT EXISTS ingestion_realtime_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL UNIQUE,
    metric_value BIGINT NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX(metric_name)
) ENGINE=InnoDB COMMENT='Real-time ingestion counters';

INSERT INTO ingestion_realtime_metrics (metric_name, metric_value) VALUES
('total_requests', 0),
('successful_bundles', 0),
('failed_bundles', 0),
('total_records_processed', 0),
('total_kafka_writes', 0),
('total_kafka_failures', 0),
('avg_processing_time_ms', 0),
('avg_bundle_size_bytes', 0)
ON DUPLICATE KEY UPDATE metric_name=metric_name;

-- ============================================================================
-- KAFKA HEALTH TABLES
-- ============================================================================

-- 6. Kafka Topic Metrics
CREATE TABLE IF NOT EXISTS kafka_topic_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    topic VARCHAR(255) NOT NULL,
    partition_count INT,
    replication_factor INT,
    message_count BIGINT,
    total_size_bytes BIGINT,
    messages_per_sec DECIMAL(10,2),
    bytes_in_per_sec BIGINT,
    bytes_out_per_sec BIGINT,
    INDEX(timestamp),
    INDEX(topic)
) ENGINE=InnoDB COMMENT='Kafka topic health and throughput metrics';

-- 7. Kafka Consumer Lag
CREATE TABLE IF NOT EXISTS kafka_consumer_lag (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    consumer_group VARCHAR(255) NOT NULL,
    topic VARCHAR(255) NOT NULL,
    partition_id INT NOT NULL,
    current_offset BIGINT,
    log_end_offset BIGINT,
    lag BIGINT,
    INDEX(timestamp),
    INDEX(consumer_group),
    INDEX(topic)
) ENGINE=InnoDB COMMENT='Consumer lag monitoring';

-- 8. Kafka Broker Metrics
CREATE TABLE IF NOT EXISTS kafka_broker_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    broker_id INT,
    broker_host VARCHAR(255),
    requests_per_sec DECIMAL(10,2),
    bytes_in_per_sec BIGINT,
    bytes_out_per_sec BIGINT,
    active_connections INT,
    INDEX(timestamp),
    INDEX(broker_id)
) ENGINE=InnoDB COMMENT='Kafka broker health metrics';

-- ============================================================================
-- SPARK PROCESSING TABLES
-- ============================================================================

-- 9. Spark Processing Metrics
CREATE TABLE IF NOT EXISTS spark_processing_metrics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    processing_mode VARCHAR(20),
    batch_id BIGINT,
    records_read BIGINT NOT NULL,
    records_processed BIGINT NOT NULL,
    records_written BIGINT NOT NULL,
    records_skipped BIGINT NOT NULL,
    records_failed BIGINT NOT NULL,
    processing_time_ms BIGINT,
    kafka_read_time_ms BIGINT,
    transformation_time_ms BIGINT,
    mysql_write_time_ms BIGINT,
    INDEX(job_id),
    INDEX(timestamp),
    INDEX(processing_mode)
) ENGINE=InnoDB COMMENT='Spark processing metrics per batch';

-- 10. Spark Failed Records
CREATE TABLE IF NOT EXISTS spark_failed_records (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL,
    batch_id BIGINT,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    failure_stage VARCHAR(50),
    record_data TEXT,
    error_type VARCHAR(100),
    error_message TEXT,
    stack_trace TEXT,
    INDEX(job_id),
    INDEX(timestamp),
    INDEX(failure_stage)
) ENGINE=InnoDB COMMENT='Failed Spark records for debugging';

-- 11. Spark Job Status
CREATE TABLE IF NOT EXISTS spark_job_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    job_id VARCHAR(255) NOT NULL UNIQUE,
    job_name VARCHAR(255),
    processing_mode VARCHAR(20),
    status VARCHAR(50),
    started_at TIMESTAMP,
    last_heartbeat TIMESTAMP,
    total_batches_processed BIGINT DEFAULT 0,
    total_records_processed BIGINT DEFAULT 0,
    total_errors BIGINT DEFAULT 0,
    INDEX(job_id),
    INDEX(status)
) ENGINE=InnoDB COMMENT='Current Spark job status';

-- ============================================================================
-- DEVOPS DASHBOARD AGGREGATIONS
-- ============================================================================

-- 12. Pipeline Health Summary
CREATE TABLE IF NOT EXISTS pipeline_health_1min (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    minute_timestamp TIMESTAMP NOT NULL,
    layer VARCHAR(50) NOT NULL,
    requests_received BIGINT,
    requests_successful BIGINT,
    requests_failed BIGINT,
    avg_processing_time_ms INT,
    p95_processing_time_ms INT,
    p99_processing_time_ms INT,
    error_rate_percent DECIMAL(5,2),
    throughput_per_sec DECIMAL(10,2),
    INDEX(minute_timestamp),
    INDEX(layer),
    UNIQUE KEY(minute_timestamp, layer)
) ENGINE=InnoDB COMMENT='1-minute aggregated metrics per layer';

-- 13. Error Summary
CREATE TABLE IF NOT EXISTS error_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    layer VARCHAR(50),
    error_type VARCHAR(100),
    error_count INT,
    sample_error_message TEXT,
    INDEX(timestamp),
    INDEX(layer),
    INDEX(error_type)
) ENGINE=InnoDB COMMENT='Error aggregations for troubleshooting';

-- Show all tables
SELECT 'All observability tables created successfully!' as status;
SHOW TABLES LIKE '%ingestion%';
SHOW TABLES LIKE '%kafka%';
SHOW TABLES LIKE '%spark%';
SHOW TABLES LIKE '%pipeline%';

