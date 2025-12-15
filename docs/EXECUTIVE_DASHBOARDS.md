# Executive Dashboards - Business Use Cases from Akamai Data

## 🎯 Overview

This document shows **what business insights** your executives can get from Akamai CDN logs, and **how to build dashboards** they'll actually use.

---

## 📊 Akamai DataStream2 Fields (70+ Available)

From your sample log, here are the key business-relevant fields:

### Performance Metrics
- `ttfb` (Time to First Byte): How fast is content delivered?
- `download_time`: How long to download complete file?
- `throughput`: Download speed (Kbps)
- `turn_around_time`: Total request processing time

### Traffic Metrics
- `bytes`: Data transferred
- `total_bytes`: Including overhead
- `uncompressed_size`: Original file size
- `obj_size`: Object size served

### Geographic Data
- `country`: User country
- `state`: User state/province
- `city`: User city
- `client_ip`: User IP address
- `edge_ip`: Edge server IP

### Request Data
- `req_method`: GET, POST, etc.
- `req_host`: Hostname requested
- `req_path`: URL path
- `req_port`: Port (80, 443)
- `http_status_code`: 200, 404, 500, etc.

### Security & Quality
- `error_code`: Delivery errors
- `security_rules`: WAF rules triggered
- `cache_status`: HIT, MISS, REFRESH
- `tls_version`: TLS1.2, TLS1.3

### Business Context
- `user_agent`: Browser/device
- `referer`: Where user came from
- `cookie`: Session tracking

---

## 🎨 Dashboard 1: Executive Overview (CEO/C-Suite)

### Purpose
**Answer: "How is our digital experience performing?"**

### Metrics

#### KPI Cards (Top Row)
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Total Traffic      │  │  Global Users       │  │  Availability       │
│  ▲ 1.2 TB          │  │  ▲ 45M requests     │  │  ✓ 99.97%          │
│  +15% vs last week  │  │  +8% vs last week   │  │  Target: 99.95%     │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Avg Performance    │  │  Error Rate         │  │  Cache Hit Rate     │
│  ▼ 187ms           │  │  ▼ 0.12%           │  │  ▲ 94.3%            │
│  -5% vs last week   │  │  -0.05% vs last wk  │  │  +2% vs last week   │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for KPI Cards:**

```sql
-- Total Traffic (Last 7 Days)
SELECT 
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    COUNT(*) AS total_requests,
    (COUNT(*) FILTER (WHERE http_status_code >= 200 AND http_status_code < 400) * 100.0 / COUNT(*)) AS availability_pct,
    AVG(ttfb) AS avg_ttfb_ms,
    (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) AS error_rate_pct,
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate_pct
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7;
```

#### Chart 1: Daily Traffic Trend (Last 30 Days)
```
Traffic (GB)
  1,500 ┤                                        ╭──
  1,400 ┤                                 ╭──────╯
  1,300 ┤                          ╭──────╯
  1,200 ┤                   ╭──────╯
  1,100 ┤            ╭──────╯
  1,000 ┤     ╭──────╯
    900 ┼─────╯
        └──────┬──────┬──────┬──────┬──────┬──────▶
             Day 1   Day 10  Day 20  Day 30
```

**SQL:**
```sql
SELECT 
    date,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 30
GROUP BY date
ORDER BY date;
```

#### Chart 2: Performance by Region (Map)
```
        North America: 145ms ✓
              │
    ┌─────────┴─────────┐
    │                   │
Europe: 178ms ✓    Asia: 234ms ⚠
    │                   │
South America: 312ms ✗  Oceania: 198ms ✓
```

**SQL:**
```sql
SELECT 
    CASE 
        WHEN country IN ('US', 'CA', 'MX') THEN 'North America'
        WHEN country IN ('GB', 'DE', 'FR', 'ES', 'IT') THEN 'Europe'
        WHEN country IN ('CN', 'JP', 'IN', 'SG', 'AU') THEN 'Asia Pacific'
        WHEN country IN ('BR', 'AR', 'CL') THEN 'South America'
        ELSE 'Other'
    END AS region,
    AVG(ttfb) AS avg_ttfb_ms,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    COUNT(DISTINCT client_ip) AS unique_users
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '24 hours'
GROUP BY region
ORDER BY traffic_gb DESC;
```

#### Chart 3: Top Content Types
```
Content Type          Traffic    Requests    Avg Size
──────────────────────────────────────────────────────
Video (mp4)           645 GB     1.2M        537 KB
Images (jpg/png)      234 GB     45M         5 KB
JavaScript            89 GB      23M         4 KB
CSS                   45 GB      12M         4 KB
HTML                  23 GB      8M          3 KB
```

**SQL:**
```sql
SELECT 
    CASE 
        WHEN req_path LIKE '%.mp4' OR req_path LIKE '%.m3u8' THEN 'Video'
        WHEN req_path LIKE '%.jpg' OR req_path LIKE '%.png' OR req_path LIKE '%.gif' THEN 'Images'
        WHEN req_path LIKE '%.js' THEN 'JavaScript'
        WHEN req_path LIKE '%.css' THEN 'CSS'
        WHEN req_path LIKE '%.html' OR req_path LIKE '%.htm' THEN 'HTML'
        ELSE 'Other'
    END AS content_type,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    COUNT(*) AS requests,
    AVG(obj_size) / 1024.0 AS avg_size_kb
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
GROUP BY content_type
ORDER BY traffic_gb DESC;
```

---

## 💰 Dashboard 2: Business Performance (CFO/COO)

### Purpose
**Answer: "Are we delivering value efficiently?"**

### Metrics

#### KPI Cards
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  CDN Cost/GB        │  │  Cache Efficiency   │  │  Bandwidth Saved    │
│  $0.08             │  │  ▲ 94.3%            │  │  ▲ $12,450         │
│  Target: $0.10      │  │  Target: 90%        │  │  vs direct serving  │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Peak Traffic Time  │  │  Wasted Bandwidth   │  │  Error Cost         │
│  8 PM - 11 PM      │  │  ▼ 2.3%            │  │  ▼ $234            │
│  45% of daily       │  │  404/500 responses  │  │  Lost revenue       │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for Cost Metrics:**

```sql
-- Daily CDN Costs (Assuming $0.085/GB in pricing tier)
SELECT 
    date,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    (SUM(bytes) / 1024.0 / 1024.0 / 1024.0) * 0.085 AS cdn_cost_usd,
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate,
    -- Calculate bandwidth saved by caching
    (SUM(bytes) FILTER (WHERE cache_status = '1') / 1024.0 / 1024.0 / 1024.0) * 0.15 AS bandwidth_saved_usd,
    -- Estimate lost revenue from errors (assuming $0.01/request)
    (COUNT(*) FILTER (WHERE http_status_code >= 400)) * 0.01 AS error_cost_usd
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
GROUP BY date
ORDER BY date;
```

#### Chart 1: Hourly Cost Pattern (Identify Peak Hours)
```
Cost ($)
  $850 ┤                        ╭────╮
  $750 ┤                    ╭───╯    ╰───╮
  $650 ┤                ╭───╯            ╰───╮
  $550 ┤            ╭───╯                    ╰───╮
  $450 ┤        ╭───╯                            ╰───╮
  $350 ┤    ╭───╯                                    ╰───╮
  $250 ┼────╯                                            ╰────
       └──┬────┬────┬────┬────┬────┬────┬────┬────┬────┬────▶
        12AM  4AM  8AM  12PM  4PM  8PM  12AM
               ↑                      ↑
            Off-peak              Peak: 8-11 PM
         (Consider pre-caching)
```

**SQL:**
```sql
SELECT 
    EXTRACT(HOUR FROM hour) AS hour_of_day,
    AVG(bytes) / 1024.0 / 1024.0 / 1024.0 AS avg_traffic_gb,
    (AVG(bytes) / 1024.0 / 1024.0 / 1024.0) * 0.085 AS avg_cost_usd
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '7 days'
GROUP BY hour_of_day
ORDER BY hour_of_day;
```

#### Chart 2: Cache Optimization Opportunities
```
Endpoint                   Cache Rate    Potential Savings
────────────────────────────────────────────────────────────
/static/images/*.jpg         99.2%       $45/month ✓ Optimized
/api/products/catalog        67.3%       $2,340/month ⚠ Action needed
/api/user/profile            12.1%       $8,900/month ✗ Critical
/static/css/*.css            98.5%       $120/month ✓ Optimized
/api/search                  45.6%       $3,400/month ⚠ Action needed
```

**SQL:**
```sql
SELECT 
    -- Extract endpoint pattern
    CASE 
        WHEN req_path LIKE '/static/images/%' THEN '/static/images/*'
        WHEN req_path LIKE '/api/products/%' THEN '/api/products/*'
        WHEN req_path LIKE '/api/user/%' THEN '/api/user/*'
        WHEN req_path LIKE '/static/css/%' THEN '/static/css/*'
        WHEN req_path LIKE '/api/search%' THEN '/api/search'
        ELSE 'Other'
    END AS endpoint_pattern,
    
    -- Calculate cache rate
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate,
    
    -- Calculate potential savings if cache rate was 95%
    (SUM(bytes) FILTER (WHERE cache_status != '1') / 1024.0 / 1024.0 / 1024.0) * 0.15 * 0.95 AS potential_savings_usd,
    
    -- Current traffic
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    COUNT(*) AS requests
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 30
GROUP BY endpoint_pattern
HAVING COUNT(*) > 10000  -- Significant endpoints only
ORDER BY potential_savings_usd DESC;
```

**Business Action:**
- **Green (>95%)**: Well optimized, no action needed
- **Yellow (70-95%)**: Review cache headers, can save $2-3K/month
- **Red (<70%)**: Critical optimization needed, $5-10K/month savings

---

## 🛡️ Dashboard 3: Security & Compliance (CTO/CISO)

### Purpose
**Answer: "Are we protecting our assets and users?"**

### Metrics

#### KPI Cards
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Security Threats   │  │  Bot Traffic        │  │  DDoS Attempts      │
│  ▼ 234             │  │  ▼ 12.3%           │  │  ▼ 3               │
│  -45% vs last week  │  │  -2% vs last week   │  │  All blocked ✓      │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  SSL/TLS Coverage   │  │  Compliance Score   │  │  GDPR Violations    │
│  ✓ 100%            │  │  ▲ 98.7%            │  │  ▼ 0               │
│  All TLS 1.2+       │  │  Target: 95%        │  │  Last 30 days       │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for Security Metrics:**

```sql
-- Security Overview (Last 24 Hours)
SELECT 
    -- Total requests
    COUNT(*) AS total_requests,
    
    -- Security threats (WAF rules triggered)
    COUNT(*) FILTER (WHERE security_rules != '') AS security_threats,
    (COUNT(*) FILTER (WHERE security_rules != '') * 100.0 / COUNT(*)) AS threat_rate,
    
    -- Bot traffic detection (based on user-agent patterns)
    COUNT(*) FILTER (WHERE user_agent LIKE '%bot%' OR user_agent LIKE '%crawler%') AS bot_requests,
    (COUNT(*) FILTER (WHERE user_agent LIKE '%bot%' OR user_agent LIKE '%crawler%') * 100.0 / COUNT(*)) AS bot_rate,
    
    -- SSL/TLS coverage
    COUNT(*) FILTER (WHERE proto = 'HTTPS') AS https_requests,
    (COUNT(*) FILTER (WHERE proto = 'HTTPS') * 100.0 / COUNT(*)) AS https_coverage,
    
    -- TLS version distribution
    COUNT(*) FILTER (WHERE tls_version = 'TLSv1.3') AS tls13_requests,
    COUNT(*) FILTER (WHERE tls_version = 'TLSv1.2') AS tls12_requests,
    COUNT(*) FILTER (WHERE tls_version NOT IN ('TLSv1.2', 'TLSv1.3')) AS old_tls_requests
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '24 hours';
```

#### Chart 1: Security Threats by Type (Last 7 Days)
```
Threat Type               Count    % Blocked    Top Countries
──────────────────────────────────────────────────────────────
SQL Injection             1,234    100%         CN, RU, US
XSS Attempts              892      100%         RU, BR, IN
Bot Attacks               645      98.5%        US, CN, DE
DDoS Attempts             12       100%         Various
Path Traversal            234      100%         RU, CN
Rate Limit Exceeded       5,678    100%         Various
```

**SQL:**
```sql
-- Parse security_rules field to extract threat types
-- Format: "ULnR_28976|3900000:3900001:3900005:3900006:BOT-ANOMALY-HEADER|"
SELECT 
    CASE 
        WHEN security_rules LIKE '%SQL%' THEN 'SQL Injection'
        WHEN security_rules LIKE '%XSS%' THEN 'XSS Attempts'
        WHEN security_rules LIKE '%BOT%' THEN 'Bot Attacks'
        WHEN security_rules LIKE '%DDOS%' THEN 'DDoS Attempts'
        WHEN security_rules LIKE '%PATH%' THEN 'Path Traversal'
        WHEN security_rules LIKE '%RATE%' THEN 'Rate Limit Exceeded'
        ELSE 'Other'
    END AS threat_type,
    COUNT(*) AS threat_count,
    -- Blocked rate (assuming error codes indicate blocks)
    (COUNT(*) FILTER (WHERE http_status_code = 403 OR http_status_code = 429) * 100.0 / COUNT(*)) AS blocked_rate,
    -- Top countries
    STRING_AGG(DISTINCT country, ', ') AS top_countries
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
  AND security_rules != ''
GROUP BY threat_type
ORDER BY threat_count DESC;
```

#### Chart 2: Geographic Risk Map
```
        🔴 High Risk (>100 threats/day)
              │
    ┌─────────┴─────────┐
    │                   │
🟡 Medium (10-100)   🟢 Low (<10)
    │                   │
```

**SQL:**
```sql
SELECT 
    country,
    COUNT(*) FILTER (WHERE security_rules != '') AS threats,
    COUNT(*) AS total_requests,
    (COUNT(*) FILTER (WHERE security_rules != '') * 100.0 / COUNT(*)) AS threat_rate,
    -- Risk level
    CASE 
        WHEN COUNT(*) FILTER (WHERE security_rules != '') > 100 THEN 'High Risk'
        WHEN COUNT(*) FILTER (WHERE security_rules != '') BETWEEN 10 AND 100 THEN 'Medium Risk'
        ELSE 'Low Risk'
    END AS risk_level
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
GROUP BY country
ORDER BY threats DESC;
```

#### Chart 3: Compliance Metrics
```
Metric                         Current    Target    Status
────────────────────────────────────────────────────────────
HTTPS Coverage                  100%       100%      ✓ Pass
TLS 1.2+ Usage                  99.8%      100%      ⚠ Near
PII Data Encryption             100%       100%      ✓ Pass
Access Logs Retention (Days)    90         90        ✓ Pass
GDPR Right to Erasure           Yes        Yes       ✓ Pass
Geographic Restrictions OK      Yes        Yes       ✓ Pass
```

---

## 👥 Dashboard 4: User Experience (Product/UX Teams)

### Purpose
**Answer: "How are users experiencing our service?"**

### Metrics

#### KPI Cards
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Avg Page Load      │  │  Mobile vs Desktop  │  │  Browser Coverage   │
│  ▼ 1.87s           │  │  Mobile: 58%        │  │  Chrome: 67%        │
│  Target: <2s ✓      │  │  Desktop: 42%       │  │  Safari: 22%        │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Error Rate         │  │  Slow Requests (>3s)│  │  User Satisfaction  │
│  ▼ 0.12%           │  │  ▼ 2.3%            │  │  ▲ 4.7 / 5.0       │
│  -0.05% vs last wk  │  │  -0.8% vs last wk   │  │  (inferred)         │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for UX Metrics:**

```sql
-- User Experience Summary (Last 24 Hours)
SELECT 
    -- Average page load time (TTFB + Download Time)
    AVG(ttfb + download_time) / 1000.0 AS avg_page_load_sec,
    
    -- Mobile vs Desktop (inferred from user-agent)
    COUNT(*) FILTER (WHERE user_agent LIKE '%Mobile%' OR user_agent LIKE '%Android%' OR user_agent LIKE '%iPhone%') AS mobile_requests,
    COUNT(*) FILTER (WHERE user_agent NOT LIKE '%Mobile%' AND user_agent NOT LIKE '%Android%' AND user_agent NOT LIKE '%iPhone%') AS desktop_requests,
    
    -- Browser distribution
    COUNT(*) FILTER (WHERE user_agent LIKE '%Chrome%') AS chrome_users,
    COUNT(*) FILTER (WHERE user_agent LIKE '%Safari%' AND user_agent NOT LIKE '%Chrome%') AS safari_users,
    COUNT(*) FILTER (WHERE user_agent LIKE '%Firefox%') AS firefox_users,
    
    -- Error rate
    (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) AS error_rate,
    
    -- Slow requests (>3 seconds)
    (COUNT(*) FILTER (WHERE (ttfb + download_time) > 3000) * 100.0 / COUNT(*)) AS slow_request_rate,
    
    -- Inferred satisfaction score (based on performance + errors)
    5.0 - (AVG(ttfb + download_time) / 1000.0) * 0.5 - (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) * 10 AS satisfaction_score
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '24 hours';
```

#### Chart 1: Performance by Device Type
```
Device          Avg TTFB    Avg Download    Total Time    % of Traffic
────────────────────────────────────────────────────────────────────────
Mobile (4G)     245ms       1.67s           1.92s         45%
Mobile (5G)     178ms       0.89s           1.07s         13%
Desktop         156ms       0.72s           0.88s         35%
Tablet          189ms       0.95s           1.14s         7%
```

**SQL:**
```sql
SELECT 
    CASE 
        WHEN user_agent LIKE '%5G%' THEN 'Mobile (5G)'
        WHEN user_agent LIKE '%Mobile%' OR user_agent LIKE '%Android%' OR user_agent LIKE '%iPhone%' THEN 'Mobile (4G)'
        WHEN user_agent LIKE '%Tablet%' OR user_agent LIKE '%iPad%' THEN 'Tablet'
        ELSE 'Desktop'
    END AS device_type,
    AVG(ttfb) AS avg_ttfb_ms,
    AVG(download_time) / 1000.0 AS avg_download_sec,
    AVG(ttfb + download_time) / 1000.0 AS avg_total_sec,
    (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()) AS pct_of_traffic
FROM akamai_hourly_metrics
WHERE hour >= NOW() - INTERVAL '7 days'
GROUP BY device_type
ORDER BY pct_of_traffic DESC;
```

#### Chart 2: User Journey Performance
```
Step                    Avg Time    Abandon Rate    Conversion
──────────────────────────────────────────────────────────────
1. Homepage Load        0.85s       5.2%            94.8%
2. Product Search       1.23s       8.7%            86.1%
3. Product Detail       1.45s       12.3%           73.8%
4. Add to Cart          0.67s       3.4%            70.4%
5. Checkout             2.34s       18.9%           51.5% ⚠
6. Payment              1.89s       9.2%            42.3%
7. Confirmation         0.92s       2.1%            40.2%
```

**SQL:**
```sql
-- Track user journey by URL patterns
SELECT 
    CASE 
        WHEN req_path = '/' THEN '1. Homepage'
        WHEN req_path LIKE '/search%' THEN '2. Search'
        WHEN req_path LIKE '/product/%' THEN '3. Product Detail'
        WHEN req_path LIKE '/cart%' THEN '4. Cart'
        WHEN req_path LIKE '/checkout%' THEN '5. Checkout'
        WHEN req_path LIKE '/payment%' THEN '6. Payment'
        WHEN req_path LIKE '/confirmation%' THEN '7. Confirmation'
        ELSE 'Other'
    END AS journey_step,
    AVG(ttfb + download_time) / 1000.0 AS avg_time_sec,
    -- Abandon rate = errors + slow responses
    (COUNT(*) FILTER (WHERE http_status_code >= 400 OR (ttfb + download_time) > 5000) * 100.0 / COUNT(*)) AS abandon_rate
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 7
GROUP BY journey_step
ORDER BY journey_step;
```

**Business Insight:**
- **Checkout step has 18.9% abandon rate** → High-priority optimization
- **Slow performance (2.34s)** → Likely causing cart abandonment
- **Potential Revenue Impact**: 18.9% × $X cart value = $Y lost revenue

---

## 🚨 Dashboard 5: Real-Time Operations (NOC/SRE)

### Purpose
**Answer: "What's happening right now?"**

### Metrics (Auto-Refresh Every 30 Seconds)

#### KPI Cards
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Current RPS        │  │  Current Bandwidth  │  │  Active Issues      │
│  ↑ 45,234          │  │  ↑ 12.3 Gbps       │  │  ⚠ 1 Warning       │
│  +12% vs 5 min ago  │  │  +8% vs 5 min ago   │  │  0 Critical         │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Avg Latency        │  │  Error Spike        │  │  Cache Hit Rate     │
│  ↑ 234ms           │  │  ⚠ +45%            │  │  ↓ 89.2%           │
│  Normal range       │  │  Last 5 minutes     │  │  -5% alert!         │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for Real-Time Metrics:**

```sql
-- Real-time metrics (Last 5 minutes)
SELECT 
    -- Current requests per second
    COUNT(*) / 300.0 AS current_rps,
    
    -- Current bandwidth (Gbps)
    SUM(bytes) * 8.0 / 300.0 / 1024.0 / 1024.0 / 1024.0 AS current_gbps,
    
    -- Average latency
    AVG(ttfb) AS avg_latency_ms,
    
    -- Error rate change
    (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) AS current_error_rate,
    (
        SELECT (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*))
        FROM akamai_raw_logs
        WHERE timestamp >= NOW() - INTERVAL '10 minutes'
          AND timestamp < NOW() - INTERVAL '5 minutes'
    ) AS prev_error_rate,
    
    -- Cache hit rate
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate
FROM akamai_raw_logs
WHERE timestamp >= NOW() - INTERVAL '5 minutes';
```

#### Chart 1: Traffic Timeline (Last Hour)
```
RPS
60K ┤                                              ╭────
55K ┤                                          ╭───╯
50K ┤                                      ╭───╯
45K ┤                                  ╭───╯
40K ┤                              ╭───╯
35K ┤                          ╭───╯
30K ┤                      ╭───╯
25K ┼──────────────────────╯
    └──┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───┬───▶
     -60m   -50m   -40m   -30m   -20m   -10m  Now
                                              ↑
                                         Spike detected
```

**SQL:**
```sql
SELECT 
    DATE_TRUNC('minute', timestamp) AS minute,
    COUNT(*) / 60.0 AS rps
FROM akamai_raw_logs
WHERE timestamp >= NOW() - INTERVAL '1 hour'
GROUP BY minute
ORDER BY minute;
```

#### Chart 2: Top Errors (Last 5 Minutes)
```
Endpoint                Status    Count    % of Traffic    Impact
──────────────────────────────────────────────────────────────────
/api/checkout           500       234      5.2%            Critical
/api/products/search    503       123      2.7%            High
/static/images/large    404       89       2.0%            Medium
/api/user/profile       502       45       1.0%            High
```

**SQL:**
```sql
SELECT 
    req_path,
    http_status_code,
    COUNT(*) AS error_count,
    (COUNT(*) * 100.0 / SUM(COUNT(*)) OVER ()) AS pct_of_errors,
    CASE 
        WHEN req_path LIKE '/api/checkout%' OR req_path LIKE '/api/payment%' THEN 'Critical'
        WHEN req_path LIKE '/api/%' THEN 'High'
        WHEN req_path LIKE '/static/%' THEN 'Medium'
        ELSE 'Low'
    END AS impact
FROM akamai_raw_logs
WHERE timestamp >= NOW() - INTERVAL '5 minutes'
  AND http_status_code >= 400
GROUP BY req_path, http_status_code
ORDER BY error_count DESC
LIMIT 10;
```

---

## 📈 Dashboard 6: Growth & Capacity Planning (VP Engineering)

### Purpose
**Answer: "Are we ready for growth?"**

### Metrics

#### KPI Cards
```
┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Monthly Growth     │  │  Capacity Used      │  │  Time to Limit      │
│  ▲ 23.4%           │  │  67.8%              │  │  6.2 months         │
│  vs last month      │  │  of current tier    │  │  (projected)        │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘

┌─────────────────────┐  ┌─────────────────────┐  ┌─────────────────────┐
│  Peak RPS Growth    │  │  Storage Growth     │  │  Cost Growth        │
│  ▲ 18.9%           │  │  ▲ 156 GB/day       │  │  ▲ 12.3%           │
│  vs last quarter    │  │  +34% vs last qtr   │  │  vs last quarter    │
└─────────────────────┘  └─────────────────────┘  └─────────────────────┘
```

**SQL for Growth Metrics:**

```sql
-- Monthly growth trend (Last 12 months)
WITH monthly_stats AS (
    SELECT 
        DATE_TRUNC('month', date) AS month,
        SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
        COUNT(*) AS requests
    FROM akamai_daily_summary
    WHERE date >= CURRENT_DATE - INTERVAL '12 months'
    GROUP BY month
)
SELECT 
    month,
    traffic_gb,
    LAG(traffic_gb) OVER (ORDER BY month) AS prev_month_traffic_gb,
    ((traffic_gb - LAG(traffic_gb) OVER (ORDER BY month)) * 100.0 / LAG(traffic_gb) OVER (ORDER BY month)) AS growth_rate
FROM monthly_stats
ORDER BY month DESC;
```

#### Chart 1: 12-Month Growth Projection
```
Traffic (TB/month)
  500 ┤                                          ╱ Forecast: 487 TB
  450 ┤                                      ╱ ╱
  400 ┤                                  ╱ ╱ ╱
  350 ┤                              ╱ ╱ ╱     Current tier limit: 500 TB
  300 ┤                          ╱ ╱ ╱         ────────────────────────────
  250 ┤                      ╱ ╱ ╱
  200 ┤                  ╱ ╱ ╱                 ⚠ Upgrade needed in 6 months
  150 ┤              ╱ ╱ ╱
  100 ┤          ╱ ╱ ╱
   50 ┤      ╱ ╱ ╱
    0 ┼──────────────────────────────────────────────────────▶
       Jan  Mar  May  Jul  Sep  Nov  Jan  Mar  May  Jul
       2025                  2026 (projected)
```

**SQL:**
```sql
-- Growth projection using linear regression
SELECT 
    DATE_TRUNC('month', date) + INTERVAL '1 month' * generate_series(0, 12) AS forecast_month,
    -- Simple linear projection (can use PostgreSQL's regr_slope for better accuracy)
    AVG(bytes) * 1.234 ^ generate_series(0, 12) / 1024.0 / 1024.0 / 1024.0 AS projected_traffic_gb
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - INTERVAL '3 months';
```

---

## 🎨 Implementation Guide

### Step 1: Set Up QuickSight Data Sources

```sql
-- Create materialized views for QuickSight (refresh hourly)

-- Executive Overview Data
CREATE MATERIALIZED VIEW mv_executive_kpis AS
SELECT 
    date,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    COUNT(*) AS total_requests,
    AVG(ttfb) AS avg_ttfb_ms,
    (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) AS error_rate,
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate,
    COUNT(DISTINCT client_ip) AS unique_users
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 90
GROUP BY date;

-- Business Performance Data
CREATE MATERIALIZED VIEW mv_business_kpis AS
SELECT 
    date,
    SUM(bytes) / 1024.0 / 1024.0 / 1024.0 AS traffic_gb,
    (SUM(bytes) / 1024.0 / 1024.0 / 1024.0) * 0.085 AS cdn_cost_usd,
    (COUNT(*) FILTER (WHERE cache_status = '1') * 100.0 / COUNT(*)) AS cache_hit_rate,
    (SUM(bytes) FILTER (WHERE cache_status = '1') / 1024.0 / 1024.0 / 1024.0) * 0.15 AS bandwidth_saved_usd
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 90
GROUP BY date;

-- Security Overview Data
CREATE MATERIALIZED VIEW mv_security_kpis AS
SELECT 
    date,
    COUNT(*) FILTER (WHERE security_rules != '') AS threats,
    (COUNT(*) FILTER (WHERE proto = 'HTTPS') * 100.0 / COUNT(*)) AS https_coverage,
    (COUNT(*) FILTER (WHERE user_agent LIKE '%bot%') * 100.0 / COUNT(*)) AS bot_rate
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 90
GROUP BY date;

-- User Experience Data
CREATE MATERIALIZED VIEW mv_ux_kpis AS
SELECT 
    date,
    AVG(ttfb + download_time) / 1000.0 AS avg_page_load_sec,
    (COUNT(*) FILTER (WHERE user_agent LIKE '%Mobile%') * 100.0 / COUNT(*)) AS mobile_pct,
    (COUNT(*) FILTER (WHERE http_status_code >= 400) * 100.0 / COUNT(*)) AS error_rate
FROM akamai_daily_summary
WHERE date >= CURRENT_DATE - 90
GROUP BY date;

-- Refresh views hourly
CREATE OR REPLACE FUNCTION refresh_quicksight_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW mv_executive_kpis;
    REFRESH MATERIALIZED VIEW mv_business_kpis;
    REFRESH MATERIALIZED VIEW mv_security_kpis;
    REFRESH MATERIALIZED VIEW mv_ux_kpis;
END;
$$ LANGUAGE plpgsql;

-- Schedule refresh (using pg_cron or external scheduler)
```

### Step 2: Create QuickSight Dashboards

**In AWS Console:**

1. **Go to QuickSight** → Create New Analysis
2. **Add Data Source**: Select RDS PostgreSQL
3. **Import Views**: mv_executive_kpis, mv_business_kpis, etc.
4. **Build Visuals**: Drag and drop fields

**Example Visual Configurations:**

```yaml
Executive Dashboard:
  KPI Cards:
    - Metric: traffic_gb
      Aggregation: SUM
      Comparison: Previous period
    - Metric: error_rate
      Aggregation: AVG
      Format: Percentage
      
  Line Chart (Traffic Trend):
    X-axis: date
    Y-axis: traffic_gb
    Color: (none)
    
  Geo Map (Performance by Region):
    Location: country
    Size: traffic_gb
    Color: avg_ttfb_ms
    
  Bar Chart (Top Content):
    Category: content_type
    Value: traffic_gb
    Sort: Descending
```

### Step 3: Share with Stakeholders

**Reader Access (Most Executives):**
- Cost: $5/user/month
- Can view, filter, export
- Cannot edit dashboards

**Author Access (Data Team):**
- Cost: $24/user/month
- Can create/edit dashboards
- Full access

**Email Subscription:**
- Schedule daily/weekly email reports
- Attach PDF snapshots
- Custom recipient lists

---

## 💡 Business Insights Summary

### What Executives Can Learn

#### CEO/C-Suite
- ✅ Overall digital performance at a glance
- ✅ User growth trends
- ✅ Service availability/reliability
- ✅ Geographic expansion opportunities

#### CFO/COO
- ✅ CDN costs and optimization opportunities
- ✅ ROI from caching improvements
- ✅ Peak traffic patterns for budgeting
- ✅ Cost per GB trends

#### CTO/CISO
- ✅ Security threat landscape
- ✅ Compliance posture
- ✅ Technical debt (old TLS versions)
- ✅ Infrastructure scaling needs

#### Product/UX
- ✅ User experience metrics (load times, errors)
- ✅ Device/browser distribution
- ✅ Conversion funnel performance
- ✅ Mobile vs desktop trends

#### VP Engineering
- ✅ Growth projections and capacity planning
- ✅ Time-to-scale estimates
- ✅ Performance SLAs tracking
- ✅ Team priorities (optimization opportunities)

---

## 📋 Dashboard Maintenance Checklist

### Daily
- [ ] Check real-time dashboard for anomalies
- [ ] Review overnight error spikes
- [ ] Verify data freshness (last refresh time)

### Weekly
- [ ] Review executive dashboard with leadership
- [ ] Update cost optimizations based on cache opportunities
- [ ] Check security threats and adjust rules

### Monthly
- [ ] Analyze month-over-month growth
- [ ] Update capacity projections
- [ ] Review compliance metrics
- [ ] Optimize slow-performing endpoints

### Quarterly
- [ ] Deep-dive into user experience trends
- [ ] Assess need for infrastructure scaling
- [ ] Review and update dashboard visuals
- [ ] Stakeholder feedback session

---

## 🚀 Next Steps

1. **Deploy Infrastructure**: Run `deploy-aws-native.sh`
2. **Load Sample Data**: Process first day of Akamai logs
3. **Create Materialized Views**: Run SQL above
4. **Build QuickSight Dashboards**: Follow Step 2
5. **Share with Executives**: Set up reader access

**Time to First Dashboard: 4 hours**

**See**: `COST_OPTIMIZED_ARCHITECTURE.md` for deployment details

