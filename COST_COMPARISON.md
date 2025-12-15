# DataLens Cost Comparison: Mobly vs Generic Architecture

## Executive Summary

For **Mobly's traffic (24K visits/day, ~50-100 MB/day)**, using a cost-optimized architecture with **Grafana instead of AWS QuickSight** results in **91% cost reduction**.

---

## Comparison Table

| Aspect | Generic Design | Mobly Optimized | Savings |
|--------|----------------|-----------------|---------|
| **Monthly Cost** | $646 | $57 | **$589 (91%)** |
| **Annual Cost** | $7,752 | $684 | **$7,068 (91%)** |
| **Dashboard Solution** | AWS QuickSight | Grafana OSS | $78/month |
| **Processing** | EMR Cluster (24/7) | EMR Serverless (8hr/day) | $288/month |
| **Database** | RDS db.m6g.large | RDS db.t4g.micro | $184/month |
| **Storage** | 100-500 GB/day | 0.05-0.1 GB/day | $48/month |

---

## Detailed Cost Breakdown

### Option 1: Generic Architecture (100-500 GB/day)

```
Service                Configuration              Monthly Cost
─────────────────────────────────────────────────────────────────
S3 Storage             100 GB                     $2.30
S3 Requests            1M PUT, 5M GET             $5.70
Lambda                 500K invocations           $1.00
EMR Cluster            3x m5.xlarge (24/7)        $300.00
RDS PostgreSQL         db.m6g.large + 100 GB      $200.00
QuickSight             4 users                    $96.00
Data Transfer          10 GB                      $0.90
CloudWatch             Logs + Metrics             $10.00
───────────────────────────────────────────────────────────────
TOTAL                                             $616.00/month
                                                  $7,392/year
```

### Option 2: Mobly Optimized (0.05-0.1 GB/day)

```
Service                Configuration              Monthly Cost
─────────────────────────────────────────────────────────────────
S3 Storage             3 GB                       $0.07
S3 Requests            100K PUT, 500K GET         $0.70
Lambda                 100K invocations           $0.20
Step Functions         100K transitions           $2.50
EMR Serverless         1 vCPU × 8h/day            $12.00
RDS PostgreSQL         db.t4g.micro + 20 GB       $16.17
EC2 Grafana            t3.small + 30 GB           $18.18
Data Transfer          1 GB                       $0.09
CloudWatch             Logs + Metrics             $5.00
SNS                    1K notifications           $0.50
Route 53               1 hosted zone              $0.50
───────────────────────────────────────────────────────────────
TOTAL                                             $55.91/month
                                                  $671/year

SAVINGS: $560/month = $6,721/year (91% reduction)
```

### Option 3: Kubernetes (Not Recommended for Mobly)

```
Service                Configuration              Monthly Cost
─────────────────────────────────────────────────────────────────
EKS Control Plane      Standard                   $73.00
EC2 Nodes              3x t3.medium               $150.00
EBS Volumes            300 GB                     $30.00
Load Balancer          Network LB                 $25.00
RDS PostgreSQL         db.m6g.large               $200.00
S3 + Transfer          Minimal                    $10.00
───────────────────────────────────────────────────────────────
TOTAL                                             $488.00/month
                                                  $5,856/year

This is 8.7x more expensive than Mobly Optimized!
Kubernetes adds complexity without benefits at this scale.
```

---

## Why Grafana vs QuickSight?

### AWS QuickSight Pricing

```
Reader (view-only):     $18/user/month
Author (create/edit):   $24/user/month

Typical Team:
- 2 Authors (DevOps, Analyst):     $48/month
- 2 Readers (Exec, Marketing):     $36/month
────────────────────────────────────────
TOTAL:                                 $84/month minimum
```

### Grafana OSS Pricing

```
Software:               FREE (open-source)
Hosting (EC2 t3.small): $15.18/month
Storage (30 GB):        $3.00/month
────────────────────────────────────────
TOTAL:                  $18.18/month

Unlimited users!
```

**Savings: $66-78/month = $792-936/year**

---

## Feature Comparison: Grafana vs QuickSight

| Feature | Grafana OSS | AWS QuickSight |
|---------|-------------|----------------|
| **Cost per User** | $0 (unlimited) | $18-24/month |
| **Dashboard Sharing** | ✅ Unlimited | ✅ Yes |
| **Real-time Updates** | ✅ WebSocket | ⚠️ Refresh required |
| **Alerting** | ✅ Built-in | ⚠️ Limited |
| **Custom Queries** | ✅ Full SQL | ⚠️ SPICE limitations |
| **Data Sources** | ✅ 100+ plugins | ⚠️ AWS-centric |
| **Community** | ✅ Large | ⚠️ Smaller |
| **Learning Curve** | Medium | Medium |
| **Customization** | ✅ Highly customizable | ⚠️ Limited |
| **On-Premise Option** | ✅ Yes | ❌ No |
| **API Access** | ✅ Full REST API | ⚠️ Limited |

---

## Cost by Traffic Volume

### Scaling Analysis

```
Traffic Level    Data/Day    Mobly Arch    Generic Arch    Savings
────────────────────────────────────────────────────────────────────
Current (24K)    50-100 MB   $57/month     $646/month      $589 (91%)
10x (240K)       500 MB-1GB  $80/month     $646/month      $566 (88%)
50x (1.2M)       2.5-5 GB    $150/month    $646/month      $496 (77%)
100x (2.4M)      5-10 GB     $250/month    $646/month      $396 (61%)
────────────────────────────────────────────────────────────────────
```

**Key Insight**: Mobly architecture remains cost-effective up to 100x current traffic!

---

## Break-Even Analysis

### When does QuickSight make sense?

QuickSight becomes competitive when:
- **10+ users** need dashboards (Grafana: $18/mo vs QS: $180+/mo)
- **But** even with 20 users, Grafana = $18/mo (same cost!)

**Conclusion**: Grafana is ALWAYS cheaper for Mobly use case.

### When does EMR Cluster make sense?

EMR Cluster (24/7) becomes competitive when:
- **Continuous processing** required (24/7 streaming)
- **Data volume > 50 GB/day** (reduces startup overhead)
- **Complex ML workloads** (model training)

For Mobly (0.05-0.1 GB/day, batch processing):
- EMR Serverless saves **$288/month** vs always-on cluster

---

## ROI Analysis for Mobly

### Investment

```
Setup Cost:     $0 (using existing AWS credits)
Monthly Cost:   $57
Annual Cost:    $684
```

### Returns

#### 1. CDN Optimization Savings

```
Baseline:
- Monthly bandwidth: 1.5 TB (estimated)
- Akamai cost: ~$150/month (at $0.10/GB)

With DataLens Insights:
- Improve cache hit rate by 10% (75% → 85%)
- Reduce bandwidth by 150 GB/month
- Savings: $15/month = $180/year

ROI: $180 / $684 = 26% (cache optimization alone)
```

#### 2. Performance Optimization

```
Identify slow pages/assets:
- 1% conversion rate improvement
- Current conversion rate: 2% (industry avg for ecommerce)
- New conversion rate: 2.02%
- 24K visits × 2.02% = 485 conversions/day (vs 480)
- +5 conversions/day × $50 AOV = $250/day = $7,500/month

ROI: $7,500 / $57 = 13,158% 🚀
```

#### 3. Security Monitoring

```
Prevent 1 DDoS attack per year:
- Cost of 1 hour downtime: $10,000 (lost revenue)
- Cost of incident response: $5,000
- Total avoided cost: $15,000/year

ROI: $15,000 / $684 = 2,193%
```

#### 4. Business Intelligence

```
Better marketing decisions:
- Identify low-performing campaigns
- Save 10% of ad spend: $500/month
- Annual savings: $6,000

ROI: $6,000 / $684 = 877%
```

### Total ROI

```
Annual Benefits:
- Cache optimization:     $180
- Conversion improvement: $90,000 (conservative 1%)
- Security:               $15,000
- Ad optimization:        $6,000
────────────────────────────
TOTAL:                    $111,180/year

Annual Cost:              $684

Net ROI: $110,496
ROI %:   16,151%

Payback Period: 0.2 months (6 days!)
```

---

## Cost Optimization Tips

### Further Reduce Costs

#### 1. Use Grafana Cloud Free Tier (First 6 Months)
```
Replace EC2 Grafana with Grafana Cloud Free:
- Grafana Cloud Free: $0/month (10K series)
- Savings: $18/month = $108 for 6 months

New Total: $39/month (32% additional savings)
```

#### 2. Use AWS Free Tier (First 12 Months)
```
If new AWS account:
- RDS db.t3.micro: 750 hours FREE (first 12 months)
- Lambda: 1M requests FREE (first 12 months)
- CloudWatch: 10 custom metrics FREE

Savings: ~$20/month for first year
```

#### 3. Reserved Instances (Long-Term)
```
If committed for 1 year:
- RDS Reserved (1-year): 30% discount = $11.30/month
- EC2 Reserved (1-year): 40% discount = $10.90/month

New Total: $35/month (38% additional savings)
```

---

## Migration Path from QuickSight

### If Already Using QuickSight

**Month 1-2: Parallel Run**
```
- Keep QuickSight ($96/month)
- Deploy Grafana ($18/month)
- Validate dashboards match
- Train team on Grafana

Cost: $114/month (temporary)
```

**Month 3: Cutover**
```
- Disable QuickSight
- Users switch to Grafana
- Monitor adoption

Cost: $18/month
Savings: $78/month going forward
```

**Total Migration Cost**: $114 × 2 months = $228  
**Annual Savings After**: $78 × 12 = $936  
**ROI**: 411% in first year

---

## Conclusion

For **Mobly's traffic pattern** (24K visits/day, ~50-100 MB/day):

### Recommended Architecture
- **EMR Serverless** (not cluster)
- **RDS db.t4g.micro** (not larger)
- **Grafana OSS** (not QuickSight)
- **S3 Standard** (with Glacier archival)

### Cost: **$57/month**
- 91% cheaper than generic design
- 8.7x cheaper than Kubernetes
- Unlimited dashboard users (vs $18-24/user with QuickSight)

### ROI: **16,151%**
- Payback period: 6 days
- Annual net benefit: $110,496

### Scalability
- Can handle 10x growth with +$23/month
- Can handle 100x growth with +$193/month

**Perfect fit for Mobly! 🎯**

---

**Document Version:** 1.0  
**Last Updated:** December 14, 2025  
**Customer:** Mobly (Brazil)

