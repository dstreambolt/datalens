-- DStreamBolt MySQL Tables for Spark Analytics
-- Run this script on the DevOps node MySQL instance

USE dstreambolt_metrics;

-- 1. Status Summary Table (for streaming aggregations by status code)
CREATE TABLE IF NOT EXISTS status_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    status INT NOT NULL,
    request_count BIGINT NOT NULL,
    avg_response_size DOUBLE,
    avg_response_time DOUBLE,
    max_response_time DOUBLE,
    min_response_time DOUBLE,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_status (status),
    INDEX idx_window_status (window_start, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Windowed aggregations by HTTP status code';

-- 2. Endpoint Summary Table (for streaming aggregations by endpoint)
CREATE TABLE IF NOT EXISTS endpoint_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    endpoint VARCHAR(500) NOT NULL,
    method VARCHAR(10) NOT NULL,
    request_count BIGINT NOT NULL,
    avg_response_time DOUBLE,
    p95_response_time DOUBLE,
    p99_response_time DOUBLE,
    unique_ips BIGINT,
    error_count BIGINT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_endpoint (endpoint(100)),
    INDEX idx_method (method),
    INDEX idx_window_endpoint (window_start, endpoint(100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Windowed aggregations by endpoint and method';

-- 3. Raw Logs Table (keep existing spark_results for batch processing)
-- This table already exists, add indexes if they don't exist
SET @exist := (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'spark_results' AND index_name = 'idx_status');
SET @sqlstmt := IF(@exist = 0, 'ALTER TABLE spark_results ADD INDEX idx_status (status)', 'SELECT ''Index idx_status already exists''');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'spark_results' AND index_name = 'idx_endpoint');
SET @sqlstmt := IF(@exist = 0, 'ALTER TABLE spark_results ADD INDEX idx_endpoint (endpoint(100))', 'SELECT ''Index idx_endpoint already exists''');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;

SET @exist := (SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = 'spark_results' AND index_name = 'idx_processing_timestamp');
SET @sqlstmt := IF(@exist = 0, 'ALTER TABLE spark_results ADD INDEX idx_processing_timestamp (processing_timestamp)', 'SELECT ''Index idx_processing_timestamp already exists''');
PREPARE stmt FROM @sqlstmt;
EXECUTE stmt;

-- 4. Error Analysis Table (for detailed error tracking)
CREATE TABLE IF NOT EXISTS error_analysis (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    status INT NOT NULL,
    endpoint VARCHAR(500) NOT NULL,
    method VARCHAR(10) NOT NULL,
    error_count BIGINT NOT NULL,
    avg_response_time DOUBLE,
    sample_ips TEXT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_status (status),
    INDEX idx_endpoint (endpoint(100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Detailed error analysis by endpoint';

-- 5. Hourly Summary Table (for long-term analytics)
CREATE TABLE IF NOT EXISTS hourly_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    hour_start TIMESTAMP NOT NULL UNIQUE,
    total_requests BIGINT NOT NULL,
    total_errors BIGINT NOT NULL,
    avg_response_time DOUBLE,
    p95_response_time DOUBLE,
    unique_ips BIGINT,
    unique_endpoints BIGINT,
    top_endpoint VARCHAR(500),
    top_endpoint_count BIGINT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_hour_start (hour_start)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Hourly aggregated statistics';

-- 6. Real-time Metrics Table (for current state/dashboard)
CREATE TABLE IF NOT EXISTS realtime_metrics (
    id INT AUTO_INCREMENT PRIMARY KEY,
    metric_name VARCHAR(100) NOT NULL UNIQUE,
    metric_value DOUBLE NOT NULL,
    metric_timestamp TIMESTAMP NOT NULL,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_metric_name (metric_name)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Current real-time metrics for dashboard';

-- Insert initial real-time metrics
INSERT INTO realtime_metrics (metric_name, metric_value, metric_timestamp) VALUES
('total_requests_last_hour', 0, NOW()),
('total_errors_last_hour', 0, NOW()),
('avg_response_time_last_hour', 0, NOW()),
('current_rps', 0, NOW()),
('error_rate_percent', 0, NOW())
ON DUPLICATE KEY UPDATE
    metric_value = VALUES(metric_value),
    metric_timestamp = VALUES(metric_timestamp);

-- Show all tables
SHOW TABLES;

-- Show table structures
DESCRIBE status_summary;
DESCRIBE endpoint_summary;
DESCRIBE error_analysis;
DESCRIBE hourly_summary;
DESCRIBE realtime_metrics;

