# DataLens Business Use Cases

## Overview

DataLens transforms raw Akamai CDN logs into actionable business insights. This document outlines practical use cases across different business functions.

---

## Table of Contents

1. [Performance Optimization](#1-performance-optimization)
2. [Security & Threat Detection](#2-security--threat-detection)
3. [Cost Optimization](#3-cost-optimization)
4. [User Experience Analytics](#4-user-experience-analytics)
5. [Content Strategy](#5-content-strategy)
6. [Capacity Planning](#6-capacity-planning)
7. [Compliance & Reporting](#7-compliance--reporting)
8. [Real-Time Operations](#8-real-time-operations)

---

## 1. Performance Optimization

### 1.1 Identify Performance Bottlenecks

**Business Problem**: Slow page load times lead to user abandonment and revenue loss.

**DataLens Solution**:

```sql
-- Find slowest endpoints in the last 24 hours
SELECT 
    reqPath,
    reqHost,
    COUNT(*) as request_count,
    AVG(timeToFirstByte) as avg_ttfb_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY timeToFirstByte) as p95_ttfb_ms,
    AVG(throughput) as avg_throughput_bps
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '24 hours'
  AND statusCode = 200
GROUP BY reqPath, reqHost
HAVING COUNT(*) > 1000
ORDER BY avg_ttfb_ms DESC
LIMIT 20;
```

**Actionable Insights**:
- Endpoints with TTFB > 2000ms need optimization
- Low throughput indicates network bottlenecks
- High request count + slow response = critical issue

**Business Impact**:
- **10% improvement in TTFB** = 1-2% increase in conversion rate
- **Reduced bounce rate** by 15-25%
- **Higher SEO rankings** (Core Web Vitals)

### 1.2 Geographic Performance Analysis

**Business Problem**: Users in certain regions experience poor performance.

**DataLens Solution**:

```sql
-- Performance by country
SELECT 
    country,
    city,
    COUNT(*) as requests,
    AVG(timeToFirstByte) as avg_ttfb_ms,
    AVG(downloadTime) as avg_download_ms,
    SUM(CASE WHEN statusCode >= 400 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as error_rate_pct
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '7 days'
GROUP BY country, city
HAVING COUNT(*) > 10000
ORDER BY avg_ttfb_ms DESC;
```

**Visualization** (Grafana):
- World heatmap colored by TTFB
- Bar chart: Top 10 slowest regions
- Time series: Performance trend by region

**Actions**:
- Add edge servers in slow regions
- Adjust origin routing
- Pre-warm caches in targeted locations

**Business Impact**:
- **50% TTFB improvement** in under-served regions
- **Expand to new markets** with confidence
- **Reduce infrastructure costs** by right-sizing capacity

### 1.3 Cache Hit Ratio Optimization

**Business Problem**: Low cache hit ratio increases origin load and costs.

**DataLens Solution**:

```sql
-- Cache efficiency by content type
SELECT 
    rspContentType,
    COUNT(*) as total_requests,
    SUM(CASE WHEN cacheStatus = 1 THEN 1 ELSE 0 END) as cache_hits,
    SUM(CASE WHEN cacheStatus = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as hit_rate_pct,
    SUM(bytes) / 1024 / 1024 / 1024 as total_gb_served,
    SUM(CASE WHEN cacheStatus = 1 THEN bytes ELSE 0 END) / 1024 / 1024 / 1024 as cached_gb
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '24 hours'
  AND statusCode = 200
GROUP BY rspContentType
ORDER BY total_requests DESC;
```

**Key Metrics**:
- **Cache Hit Ratio**: Target > 90% for static assets
- **Origin Offload**: Bytes served from cache vs origin
- **Byte Hit Ratio**: (cached_gb / total_gb) * 100

**Actions**:
- Increase TTL for static content
- Add Cache-Control headers
- Pre-populate cache for popular content

**Business Impact**:
- **80% → 95% hit ratio** = 75% reduction in origin requests
- **$50K/month** saved on origin infrastructure
- **Faster response times** (cache hits are 10x faster)

---

## 2. Security & Threat Detection

### 2.1 DDoS Attack Detection

**Business Problem**: DDoS attacks can take down websites and cost millions in lost revenue.

**DataLens Solution**:

```sql
-- Detect unusual traffic spikes
SELECT 
    time_bucket('1 minute', request_timestamp) as time,
    COUNT(*) as requests_per_minute,
    COUNT(DISTINCT cliIP) as unique_ips,
    SUM(CASE WHEN statusCode >= 400 THEN 1 ELSE 0 END) as error_count
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '1 hour'
GROUP BY time
ORDER BY time DESC;

-- Identify attack sources
SELECT 
    cliIP,
    country,
    COUNT(*) as request_count,
    COUNT(DISTINCT reqPath) as unique_paths,
    SUM(CASE WHEN statusCode = 429 THEN 1 ELSE 0 END) as rate_limited,
    MAX(request_timestamp) as last_seen
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '5 minutes'
GROUP BY cliIP, country
HAVING COUNT(*) > 1000
ORDER BY request_count DESC;
```

**Alerts** (Grafana):
- Trigger alert when: `requests_per_minute > 10 * baseline`
- Threshold: `requests_per_minute > 100,000`
- Notification: PagerDuty, Slack, Email

**Actions**:
- Automatically block attacking IPs
- Enable rate limiting
- Activate WAF rules
- Scale up infrastructure

**Business Impact**:
- **Detect attacks in < 2 minutes** (vs 15-30 minutes manually)
- **Prevent downtime** (99.99% uptime maintained)
- **Protect revenue** during high-traffic events (Black Friday, product launches)

### 2.2 Bot Traffic Analysis

**Business Problem**: Bots waste bandwidth, skew analytics, and scrape content.

**DataLens Solution**:

```sql
-- Identify bot traffic patterns
SELECT 
    UA as user_agent,
    COUNT(*) as request_count,
    COUNT(DISTINCT cliIP) as unique_ips,
    AVG(throughput) as avg_throughput,
    SUM(bytes) / 1024 / 1024 as total_mb,
    -- Bot indicators
    CASE 
        WHEN UA LIKE '%bot%' OR UA LIKE '%crawler%' THEN 'Known Bot'
        WHEN COUNT(*) / COUNT(DISTINCT reqPath) < 2 THEN 'Scraper'
        WHEN AVG(throughput) > 50000000 THEN 'High-Speed Bot'
        ELSE 'Likely Human'
    END as traffic_type
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '24 hours'
GROUP BY UA
HAVING COUNT(*) > 100
ORDER BY request_count DESC;
```

**Advanced Detection**:
- Abnormal request patterns (too fast, too uniform)
- Suspicious user agents
- Geographic clustering
- Headless browser fingerprints

**Actions**:
- Challenge with CAPTCHA
- Rate limit by IP/user agent
- Block malicious bots
- Allow good bots (Google, Bing crawlers)

**Business Impact**:
- **40% reduction** in wasteful bandwidth
- **Accurate analytics** (exclude bot traffic)
- **Content protection** from scraping
- **Cost savings**: $10K-50K/month on bandwidth

### 2.3 Security Rule Effectiveness

**Business Problem**: Are WAF rules protecting without blocking legitimate users?

**DataLens Solution**:

```sql
-- WAF rule trigger analysis
SELECT 
    securityRules,
    COUNT(*) as trigger_count,
    COUNT(DISTINCT cliIP) as unique_ips,
    COUNT(DISTINCT country) as countries,
    AVG(CASE WHEN statusCode = 403 THEN 1 ELSE 0 END) * 100 as block_rate_pct
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '7 days'
  AND securityRules IS NOT NULL
  AND securityRules != ''
GROUP BY securityRules
ORDER BY trigger_count DESC;
```

**Visualization**:
- Sankey diagram: Attack type → Rule → Action
- Time series: Rule triggers over time
- Geo map: Attack origin countries

**Actions**:
- Tune overly aggressive rules (high false positive rate)
- Strengthen weak rules (high bypass rate)
- Add new rules for emerging threats

**Business Impact**:
- **95% attack blocking** with < 0.1% false positives
- **Compliance**: Maintain PCI DSS, HIPAA requirements
- **Trust**: Protect customer data

---

## 3. Cost Optimization

### 3.1 Origin Offload Analysis

**Business Problem**: Excessive origin requests drive up infrastructure costs.

**DataLens Solution**:

```sql
-- Calculate origin offload savings
WITH cache_metrics AS (
    SELECT 
        time_bucket('1 hour', request_timestamp) as hour,
        COUNT(*) as total_requests,
        SUM(CASE WHEN cacheStatus = 1 THEN 1 ELSE 0 END) as cache_hits,
        SUM(bytes) as total_bytes,
        SUM(CASE WHEN cacheStatus = 1 THEN bytes ELSE 0 END) as cached_bytes
    FROM akamai_logs
    WHERE request_timestamp > NOW() - INTERVAL '30 days'
    GROUP BY hour
)
SELECT 
    AVG(cache_hits * 100.0 / NULLIF(total_requests, 0)) as avg_hit_rate_pct,
    SUM(cached_bytes) / 1024 / 1024 / 1024 as total_cached_gb,
    SUM(total_bytes - cached_bytes) / 1024 / 1024 / 1024 as origin_served_gb,
    -- Cost calculation (example: $0.10/GB origin bandwidth)
    SUM(total_bytes - cached_bytes) / 1024 / 1024 / 1024 * 0.10 as origin_cost_usd,
    SUM(cached_bytes) / 1024 / 1024 / 1024 * 0.10 as cost_if_not_cached
FROM cache_metrics;
```

**ROI Calculation**:
```
If cache hit ratio improves from 80% to 95%:
- Origin requests: -75%
- Origin bandwidth: -75%
- Monthly savings: $40K (for 100TB/month traffic)
```

**Actions**:
- Increase cache TTL for static assets
- Implement edge caching for dynamic content
- Use stale-while-revalidate

**Business Impact**:
- **$200K-500K/year** saved on origin infrastructure
- **Better origin performance** (lower load)
- **Scalability**: Handle 10x traffic without scaling origin

### 3.2 Content Delivery Efficiency

**Business Problem**: Serving large files to distant users is expensive.

**DataLens Solution**:

```sql
-- Identify expensive traffic patterns
SELECT 
    country,
    rspContentType,
    fileSizeBucket,
    COUNT(*) as request_count,
    SUM(bytes) / 1024 / 1024 / 1024 as total_gb,
    -- Estimate cost (AWS CloudFront pricing example)
    CASE 
        WHEN country IN ('US', 'CA', 'EU') THEN SUM(bytes) / 1024 / 1024 / 1024 * 0.085
        WHEN country IN ('JP', 'AU', 'IN') THEN SUM(bytes) / 1024 / 1024 / 1024 * 0.140
        WHEN country IN ('SA', 'AF') THEN SUM(bytes) / 1024 / 1024 / 1024 * 0.170
        ELSE SUM(bytes) / 1024 / 1024 / 1024 * 0.200
    END as estimated_cost_usd
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '30 days'
GROUP BY country, rspContentType, fileSizeBucket
ORDER BY estimated_cost_usd DESC
LIMIT 50;
```

**Optimization Strategies**:
1. **Compression**: Enable Brotli/gzip for text files
   - Savings: 60-80% for HTML/CSS/JS
2. **Adaptive Bitrate**: Serve lower quality to mobile/slow connections
   - Savings: 30-50% for video
3. **Image Optimization**: WebP format, lazy loading
   - Savings: 40-60% for images
4. **Regional Pricing**: Route traffic through cheaper regions when possible

**Business Impact**:
- **30% reduction** in CDN costs
- **Faster delivery** (smaller files)
- **Better UX** (optimized for device/network)

---

## 4. User Experience Analytics

### 4.1 Download Completion Rate

**Business Problem**: Users abandoning downloads indicates poor UX.

**DataLens Solution**:

```sql
-- Download completion analysis
SELECT 
    rspContentType,
    fileSizeBucket,
    country,
    COUNT(*) as total_downloads,
    SUM(downloadInitiated) as initiated,
    SUM(downloadsCompleted) as completed,
    SUM(downloadsCompleted) * 100.0 / NULLIF(SUM(downloadInitiated), 0) as completion_rate_pct,
    AVG(downloadTime) as avg_download_ms
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '7 days'
  AND downloadInitiated = 1
GROUP BY rspContentType, fileSizeBucket, country
HAVING SUM(downloadInitiated) > 100
ORDER BY completion_rate_pct ASC;
```

**Red Flags**:
- Completion rate < 80% for any content type
- Large files in slow regions (high abandonment)
- Mobile users with lower completion rates

**Actions**:
- Implement resume capability
- Use adaptive streaming for video
- Pre-buffer content
- Show download progress indicators

**Business Impact**:
- **+15% completion rate** = more engaged users
- **Higher retention** (users don't give up)
- **More revenue** (completed downloads lead to conversions)

### 4.2 Error Rate by User Segment

**Business Problem**: Errors frustrate users and cause churn.

**DataLens Solution**:

```sql
-- Error analysis by device/browser
SELECT 
    CASE 
        WHEN UA LIKE '%Mobile%' THEN 'Mobile'
        WHEN UA LIKE '%Tablet%' THEN 'Tablet'
        ELSE 'Desktop'
    END as device_type,
    statusCode,
    errorCode,
    COUNT(*) as error_count,
    COUNT(DISTINCT cliIP) as affected_users,
    AVG(timeToFirstByte) as avg_ttfb_ms
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '24 hours'
  AND statusCode >= 400
GROUP BY device_type, statusCode, errorCode
ORDER BY error_count DESC;
```

**Common Issues**:
- **404 errors**: Broken links, outdated content
- **502/503 errors**: Origin overload or downtime
- **403 errors**: Geo-blocking, authentication issues
- **Mobile-specific errors**: Compatibility issues

**Actions**:
- Fix broken links (404s)
- Add redirects for moved content (301s)
- Scale origin servers (502/503s)
- Improve mobile compatibility

**Business Impact**:
- **50% reduction** in error rate
- **Higher user satisfaction** (NPS +10 points)
- **Reduced support tickets** (30% fewer error-related calls)

### 4.3 Performance by Device & Network

**Business Problem**: Mobile users on slow networks have poor experience.

**DataLens Solution**:

```sql
-- Performance segmentation
SELECT 
    CASE 
        WHEN UA LIKE '%Mobile%' THEN 'Mobile'
        WHEN UA LIKE '%Tablet%' THEN 'Tablet'
        ELSE 'Desktop'
    END as device,
    CASE 
        WHEN throughput > 10000000 THEN 'Fast (>10Mbps)'
        WHEN throughput > 5000000 THEN 'Medium (5-10Mbps)'
        WHEN throughput > 1000000 THEN 'Slow (1-5Mbps)'
        ELSE 'Very Slow (<1Mbps)'
    END as network_speed,
    COUNT(*) as request_count,
    AVG(timeToFirstByte) as avg_ttfb_ms,
    AVG(downloadTime) as avg_download_ms,
    PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY downloadTime) as p95_download_ms
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '7 days'
  AND statusCode = 200
  AND downloadInitiated = 1
GROUP BY device, network_speed
ORDER BY device, network_speed;
```

**Optimization Matrix**:
| Device  | Network | Action |
|---------|---------|--------|
| Mobile  | Slow    | Low-res images, simplified layout |
| Mobile  | Fast    | HD content, rich media |
| Desktop | Slow    | Prioritize critical content |
| Desktop | Fast    | Full experience |

**Business Impact**:
- **40% faster load times** on slow networks
- **Inclusive UX** (all users get good experience)
- **Higher engagement** from mobile users (+25%)

---

## 5. Content Strategy

### 5.1 Popular Content Analysis

**Business Problem**: What content resonates with users?

**DataLens Solution**:

```sql
-- Top content by engagement
SELECT 
    reqPath,
    reqHost,
    COUNT(*) as views,
    COUNT(DISTINCT cliIP) as unique_viewers,
    SUM(bytes) / 1024 / 1024 as total_mb_served,
    AVG(downloadTime) as avg_view_duration_ms,
    SUM(downloadsCompleted) * 100.0 / SUM(downloadInitiated) as completion_rate_pct
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '30 days'
  AND statusCode = 200
  AND rspContentType LIKE '%video%'
GROUP BY reqPath, reqHost
HAVING COUNT(*) > 100
ORDER BY views DESC
LIMIT 100;
```

**Content Metrics**:
- **View Count**: Total views
- **Unique Viewers**: Reach
- **Completion Rate**: Engagement quality
- **Average View Duration**: Content quality

**Actions**:
- Promote popular content
- Create similar content
- Sunset unpopular content
- A/B test variations

**Business Impact**:
- **30% increase** in content ROI
- **Data-driven** content decisions
- **Higher engagement** (focus on what works)

### 5.2 Content Freshness & Staleness

**Business Problem**: Outdated cached content leads to user confusion.

**DataLens Solution**:

```sql
-- Identify stale content
SELECT 
    reqPath,
    MAX(maxAgeSec) as cache_ttl_seconds,
    MAX(maxAgeSec) / 3600.0 as cache_ttl_hours,
    COUNT(*) as request_count,
    MAX(request_timestamp) as last_requested,
    EXTRACT(EPOCH FROM (NOW() - MAX(request_timestamp))) / 3600 as hours_since_last_request
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '30 days'
  AND cacheStatus = 1
GROUP BY reqPath
HAVING MAX(maxAgeSec) > 86400  -- TTL > 1 day
ORDER BY cache_ttl_hours DESC;
```

**Recommendations**:
- Dynamic content: TTL < 1 hour
- Semi-static (news): TTL = 5-15 minutes
- Static assets: TTL = 1 day - 1 year
- User-specific: No-cache

**Business Impact**:
- **Reduced stale content** complaints
- **Fresher user experience**
- **Balance**: Fresh vs cache efficiency

---

## 6. Capacity Planning

### 6.1 Traffic Forecasting

**Business Problem**: Under-provisioning causes outages; over-provisioning wastes money.

**DataLens Solution**:

```sql
-- Historical traffic patterns for forecasting
SELECT 
    date_trunc('hour', request_timestamp) as hour,
    EXTRACT(dow FROM request_timestamp) as day_of_week,
    EXTRACT(hour FROM request_timestamp) as hour_of_day,
    COUNT(*) as request_count,
    SUM(bytes) / 1024 / 1024 / 1024 as gb_served,
    AVG(timeToFirstByte) as avg_ttfb_ms,
    MAX(timeToFirstByte) as max_ttfb_ms
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '90 days'
GROUP BY hour, day_of_week, hour_of_day
ORDER BY hour;
```

**Forecasting Models**:
1. **Seasonal patterns**: Weekly/monthly cycles
2. **Growth trends**: Linear/exponential
3. **Event-driven spikes**: Product launches, sales
4. **Anomaly detection**: Unexpected traffic

**Capacity Planning**:
```
Peak traffic = Historical_peak * Growth_factor * Event_multiplier * Safety_margin
Example: 100K req/s * 1.2 (20% growth) * 1.5 (Black Friday) * 1.3 (safety) = 234K req/s
```

**Business Impact**:
- **99.99% uptime** during peak events
- **15% cost savings** (right-sized infrastructure)
- **Confident scaling** for business growth

### 6.2 EdgeWorkers Usage & Scaling

**Business Problem**: EdgeWorkers improve performance but have limits.

**DataLens Solution**:

```sql
-- EdgeWorkers execution analysis
SELECT 
    SUBSTRING(ewExecutionInfo, 1, 50) as edgeworker_id,
    COUNT(*) as execution_count,
    AVG(CAST(SPLIT_PART(SPLIT_PART(ewExecutionInfo, ':', 7), '|', 1) AS INTEGER)) as avg_duration_ms,
    SUM(CASE WHEN ewExecutionInfo LIKE '%200%' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as success_rate_pct,
    SUM(bytes) / 1024 / 1024 as total_mb_processed
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '7 days'
  AND ewExecutionInfo IS NOT NULL
  AND ewExecutionInfo != ''
GROUP BY edgeworker_id
ORDER BY execution_count DESC;
```

**Optimization**:
- Functions taking > 50ms: Optimize or move to origin
- Low success rate: Debug and fix
- High volume: Consider caching results

**Business Impact**:
- **30% faster** dynamic content
- **Reduced origin load** (edge processing)
- **Better UX** (personalization at the edge)

---

## 7. Compliance & Reporting

### 7.1 GDPR Compliance

**Business Problem**: Must handle user data according to GDPR.

**DataLens Solution**:

```sql
-- Geographic data processing report
SELECT 
    country,
    COUNT(*) as request_count,
    COUNT(DISTINCT cliIP) as unique_users,
    SUM(bytes) / 1024 / 1024 / 1024 as data_transferred_gb,
    -- Data retention check
    COUNT(CASE WHEN request_timestamp < NOW() - INTERVAL '90 days' THEN 1 END) as records_to_purge
FROM akamai_logs
WHERE country IN ('DE', 'FR', 'GB', 'IT', 'ES')  -- EU countries
GROUP BY country;
```

**GDPR Actions**:
1. **Right to be Forgotten**: Delete user data on request
2. **Data Minimization**: Store only necessary fields
3. **Anonymization**: Hash/mask IP addresses after 7 days
4. **Data Portability**: Export user data in JSON

**Implementation**:
```sql
-- Anonymize old data
UPDATE akamai_logs
SET cliIP = 'ANONYMIZED',
    cookie = NULL,
    xForwardedFor = NULL
WHERE request_timestamp < NOW() - INTERVAL '7 days';
```

**Business Impact**:
- **Compliance**: Avoid €20M or 4% revenue fines
- **Trust**: Users appreciate data protection
- **Competitive advantage**: Privacy as a feature

### 7.2 SLA Reporting

**Business Problem**: Must prove 99.9% uptime to customers.

**DataLens Solution**:

```sql
-- Monthly SLA report
WITH hourly_availability AS (
    SELECT 
        time_bucket('1 hour', request_timestamp) as hour,
        COUNT(*) as total_requests,
        SUM(CASE WHEN statusCode < 500 THEN 1 ELSE 0 END) as successful_requests,
        SUM(CASE WHEN statusCode >= 500 THEN 1 ELSE 0 END) as server_errors
    FROM akamai_logs
    WHERE request_timestamp >= date_trunc('month', CURRENT_DATE)
    GROUP BY hour
)
SELECT 
    COUNT(*) as total_hours,
    SUM(total_requests) as total_requests,
    SUM(successful_requests) * 100.0 / SUM(total_requests) as success_rate_pct,
    COUNT(CASE WHEN successful_requests * 100.0 / total_requests < 99.0 THEN 1 END) as hours_below_sla,
    -- Uptime calculation
    (COUNT(*) - COUNT(CASE WHEN successful_requests * 100.0 / total_requests < 99.0 THEN 1 END)) * 100.0 / COUNT(*) as uptime_pct
FROM hourly_availability;
```

**SLA Tiers**:
- **99.9% uptime**: 43 minutes downtime/month allowed
- **99.95% uptime**: 21 minutes downtime/month allowed
- **99.99% uptime**: 4.3 minutes downtime/month allowed

**Business Impact**:
- **Transparent reporting** to customers
- **Proactive issue detection** (before SLA breach)
- **Trust**: Demonstrate reliability

---

## 8. Real-Time Operations

### 8.1 Real-Time Traffic Dashboard

**Business Problem**: Operations team needs live view of system health.

**DataLens Solution**:

Grafana dashboard with:
- **Current request rate**: Requests/sec (updated every 5 sec)
- **Error rate**: % of 4xx/5xx responses
- **Top endpoints**: By traffic
- **Geographic heatmap**: Live traffic by country
- **Alert banner**: Active incidents

**Queries** (via Kafka streaming):
```sql
-- Real-time request rate (5-second window)
SELECT 
    COUNT(*) / 5.0 as requests_per_second
FROM akamai_logs
WHERE request_timestamp > NOW() - INTERVAL '5 seconds';
```

**Alerting Rules**:
```yaml
# Grafana alert
- alert: HighErrorRate
  expr: (sum(rate(akamai_errors_total[5m])) / sum(rate(akamai_requests_total[5m]))) > 0.05
  for: 2m
  labels:
    severity: critical
  annotations:
    summary: "Error rate > 5% for 2 minutes"
```

**Business Impact**:
- **Mean Time to Detect (MTTD)**: < 2 minutes
- **Mean Time to Resolve (MTTR)**: Reduced by 50%
- **Proactive response**: Fix issues before users complain

### 8.2 Automated Incident Response

**Business Problem**: Manual incident response is slow and error-prone.

**DataLens Solution**:

Automated playbooks triggered by alerts:

```python
# Example: Auto-scale on traffic spike
if requests_per_minute > threshold * 1.5:
    # 1. Alert operations team
    send_alert("Traffic spike detected", severity="warning")
    
    # 2. Auto-scale Kubernetes pods
    kubectl.scale("deployment/spark-executor", replicas=16)
    
    # 3. Enable rate limiting
    akamai_api.enable_rate_limiting(limit=10000)
    
    # 4. Notify stakeholders
    send_slack_message("#ops", "Auto-scaled to handle traffic spike")
```

**Incident Types**:
1. **Traffic spike**: Auto-scale
2. **High error rate**: Investigate + notify
3. **Origin down**: Failover to backup
4. **DDoS attack**: Enable mitigation + block IPs
5. **Slow response**: Check origin health

**Business Impact**:
- **Automated response**: No human in the loop for 80% of incidents
- **Faster resolution**: 5 minutes vs 30 minutes
- **Reduced on-call burden**: Better work-life balance for ops team

---

## Summary

DataLens enables data-driven decision making across all aspects of CDN operations:

| Use Case | Key Metric | Business Impact |
|----------|------------|-----------------|
| Performance Optimization | TTFB, Throughput | +2% conversion rate |
| Security | Attack detection time | 99.99% uptime |
| Cost Optimization | Cache hit ratio | $200K-500K/year savings |
| User Experience | Error rate, Completion rate | +15% user satisfaction |
| Content Strategy | View count, Engagement | +30% content ROI |
| Capacity Planning | Traffic forecast accuracy | Right-sized infrastructure |
| Compliance | Data retention, SLA | Avoid fines, maintain trust |
| Real-Time Ops | MTTD, MTTR | 50% faster incident resolution |

**Total Business Value**: $500K-2M annually (for typical mid-size company)

---

## Next Steps

1. **Prioritize** use cases based on your business needs
2. **Implement** dashboards for top 3 use cases
3. **Iterate** based on feedback and new insights
4. **Expand** to advanced analytics (ML, anomaly detection)

**Questions?** Contact: support@datalens.io

