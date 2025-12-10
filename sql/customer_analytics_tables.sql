-- Customer Analytics Tables for Spark Processed Data
-- These tables store the aggregated customer request data from log processing

USE dstreambolt_metrics;

-- Status Code Summary (aggregated by time window and status code)
CREATE TABLE IF NOT EXISTS status_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    status INT NOT NULL,
    request_count BIGINT NOT NULL DEFAULT 0,
    avg_response_time DOUBLE,
    p95_response_time DOUBLE,
    p99_response_time DOUBLE,
    unique_ips INT,
    error_count BIGINT DEFAULT 0,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_status (status),
    INDEX idx_window_status (window_start, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Endpoint Performance Summary (aggregated by endpoint)
CREATE TABLE IF NOT EXISTS endpoint_summary (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    endpoint VARCHAR(500) NOT NULL,
    method VARCHAR(10) NOT NULL,
    status INT,
    request_count BIGINT NOT NULL DEFAULT 0,
    avg_response_time DOUBLE,
    p95_response_time DOUBLE,
    p99_response_time DOUBLE,
    unique_ips INT,
    error_count BIGINT DEFAULT 0,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_endpoint (endpoint(100)),
    INDEX idx_window_endpoint (window_start, endpoint(100))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Customer Request Details (individual parsed log entries)
CREATE TABLE IF NOT EXISTS customer_requests (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP NOT NULL,
    ip VARCHAR(45) NOT NULL,
    method VARCHAR(10) NOT NULL,
    endpoint VARCHAR(500) NOT NULL,
    status INT NOT NULL,
    response_size INT,
    response_time DOUBLE,
    user_agent VARCHAR(500),
    referer VARCHAR(500),
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_timestamp (timestamp),
    INDEX idx_status (status),
    INDEX idx_endpoint (endpoint(100)),
    INDEX idx_ip (ip)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- IP Analytics (aggregated by IP address)
CREATE TABLE IF NOT EXISTS ip_analytics (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    ip VARCHAR(45) NOT NULL,
    request_count BIGINT NOT NULL DEFAULT 0,
    error_count BIGINT DEFAULT 0,
    avg_response_time DOUBLE,
    endpoints_accessed INT,
    total_bytes BIGINT,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_ip (ip),
    UNIQUE KEY unique_window_ip (window_start, ip)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- User Agent Analytics
CREATE TABLE IF NOT EXISTS user_agent_stats (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    window_start TIMESTAMP NOT NULL,
    window_end TIMESTAMP NOT NULL,
    user_agent VARCHAR(500) NOT NULL,
    device_type VARCHAR(50),
    request_count BIGINT NOT NULL DEFAULT 0,
    avg_response_time DOUBLE,
    processing_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_window_start (window_start),
    INDEX idx_device_type (device_type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

