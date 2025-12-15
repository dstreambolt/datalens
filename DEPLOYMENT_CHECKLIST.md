# DataLens - Deployment Checklist ✅

Use this checklist to ensure a successful deployment of DataLens.

---

## 📋 Pre-Deployment Checklist

### Infrastructure Requirements
- [ ] Kubernetes cluster available (EKS/GKE/AKS/minikube)
  - [ ] At least 3 worker nodes
  - [ ] 8+ vCPU per node
  - [ ] 16+ GB RAM per node
  - [ ] 200+ GB storage
- [ ] kubectl installed and configured
  - [ ] `kubectl version --client`
  - [ ] `kubectl cluster-info`
- [ ] helm 3.x installed
  - [ ] `helm version`
- [ ] Docker installed (for building images)
  - [ ] `docker --version`

### AWS Requirements
- [ ] AWS account with S3 access
- [ ] AWS CLI installed and configured
  - [ ] `aws --version`
  - [ ] `aws s3 ls` (test access)
- [ ] S3 bucket created for Akamai logs
  - [ ] Bucket name: `________________________`
  - [ ] Region: `________________________`
- [ ] IAM user/role with S3 read permissions
  - [ ] Access Key ID: `________________________`
  - [ ] Secret Access Key: (stored securely)

### Akamai Configuration
- [ ] Akamai DataStream2 configured
  - [ ] Destination: Amazon S3
  - [ ] Bucket: `________________________`
  - [ ] Prefix: `logs/`
  - [ ] Format: Space-delimited
  - [ ] Compression: gzip
  - [ ] Upload frequency: 5 minutes

---

## 🚀 Deployment Steps

### 1. Repository Setup
- [ ] Clone DataLens repository
  ```bash
  git clone https://github.com/yourusername/datalens.git
  cd datalens
  ```
- [ ] Review README.md
- [ ] Review QUICK_START.md

### 2. Configuration
- [ ] Set environment variables
  ```bash
  export AWS_ACCESS_KEY_ID="your-key"
  export AWS_SECRET_ACCESS_KEY="your-secret"
  export S3_BUCKET="your-bucket-name"
  export AWS_REGION="us-east-1"
  ```
- [ ] Update configmaps (if needed)
  - [ ] S3 bucket name in `k8s/configmaps.yaml`
  - [ ] AWS region
  - [ ] Kafka configuration

### 3. Automated Deployment
- [ ] Run deployment script
  ```bash
  ./scripts/deploy-all.sh
  ```
- [ ] Watch deployment progress
- [ ] Note down generated passwords
  - [ ] Grafana admin password: `________________________`
  - [ ] TimescaleDB password: `________________________`

### 4. Manual Verification
- [ ] Check namespace created
  ```bash
  kubectl get namespace datalens
  ```
- [ ] Check pods are running
  ```bash
  kubectl get pods -n datalens
  ```
  - [ ] Spark operator: Running
  - [ ] Kafka (3 brokers): Running
  - [ ] TimescaleDB: Running
  - [ ] Grafana: Running
  - [ ] MinIO: Running

### 5. Service Verification
- [ ] Kafka topics created
  ```bash
  kubectl exec kafka-0 -n datalens -- kafka-topics.sh --list --bootstrap-server localhost:9092
  ```
  - [ ] akamai-raw-logs
  - [ ] akamai-processed-metrics
  - [ ] akamai-alerts

- [ ] TimescaleDB schema initialized
  ```bash
  kubectl exec timescaledb-0 -n datalens -- psql -U postgres -d datalens_metrics -c "\dt"
  ```
  - [ ] akamai_logs table exists
  - [ ] akamai_hourly_metrics view exists

- [ ] Grafana accessible
  ```bash
  kubectl port-forward svc/grafana 3000:80 -n datalens
  ```
  - [ ] Open http://localhost:3000
  - [ ] Login successful (admin / password)

---

## 🧪 Testing

### 1. Pipeline Test
- [ ] Run test pipeline script
  ```bash
  ./scripts/test-pipeline.sh
  ```
- [ ] Verify sample data generated
  - [ ] Sample logs created: Yes / No
  - [ ] Uploaded to S3: Yes / No
  - [ ] Spark job triggered: Yes / No

### 2. Data Verification
- [ ] Check data in TimescaleDB
  ```bash
  kubectl exec timescaledb-0 -n datalens -- psql -U postgres -d datalens_metrics -c "SELECT COUNT(*) FROM akamai_logs;"
  ```
  - [ ] Record count: `________________________`

- [ ] Check data in Kafka
  ```bash
  kubectl exec kafka-0 -n datalens -- kafka-run-class.sh kafka.tools.GetOffsetShell --broker-list localhost:9092 --topic akamai-raw-logs
  ```
  - [ ] Message count: `________________________`

### 3. Query Testing
- [ ] Run sample queries
  - [ ] Request count by country
  - [ ] Error rate analysis
  - [ ] Cache hit ratio
  - [ ] Top endpoints
- [ ] Query response time < 1 second: Yes / No

---

## 📊 Dashboard Setup

### Grafana Configuration
- [ ] Add TimescaleDB data source
  - [ ] Host: `timescaledb.datalens.svc.cluster.local:5432`
  - [ ] Database: `datalens_metrics`
  - [ ] User: `postgres`
  - [ ] Test connection: Successful

- [ ] Import dashboards
  - [ ] Performance Analytics
  - [ ] Security Monitoring
  - [ ] Geographic Insights
  - [ ] Cache Efficiency
  - [ ] EdgeWorkers Analytics

- [ ] Configure alerts
  - [ ] Error rate > 5%
  - [ ] TTFB > 2000ms
  - [ ] Cache hit ratio < 80%

---

## 🔐 Security Hardening

### Secrets Management
- [ ] Rotate default passwords
  - [ ] Grafana admin password
  - [ ] TimescaleDB password
- [ ] Store secrets securely (not in Git)
- [ ] Use Kubernetes Secrets for all credentials

### Network Security
- [ ] Enable network policies
- [ ] Configure ingress with TLS
- [ ] Restrict pod-to-pod communication
- [ ] Set up firewall rules

### Access Control
- [ ] Configure RBAC
  - [ ] DevOps role (full access)
  - [ ] Developer role (read-only)
  - [ ] Analyst role (dashboard only)
- [ ] Set up audit logging
- [ ] Enable MFA for admin accounts

---

## 📈 Monitoring Setup

### Metrics Collection
- [ ] Deploy Prometheus (optional)
  ```bash
  helm install prometheus prometheus-community/prometheus -n datalens
  ```
- [ ] Configure Prometheus to scrape:
  - [ ] Spark metrics
  - [ ] Kafka metrics
  - [ ] TimescaleDB metrics
  - [ ] Pod metrics

### Alerting
- [ ] Configure alert channels
  - [ ] Email: `________________________`
  - [ ] Slack webhook: `________________________`
  - [ ] PagerDuty: `________________________`

- [ ] Set up alert rules
  - [ ] Spark job failures
  - [ ] Kafka consumer lag > 1 hour
  - [ ] Disk usage > 80%
  - [ ] Query latency > 5 seconds

### Logging
- [ ] Set up centralized logging (optional)
  - [ ] ELK Stack or Loki
  - [ ] Log retention: 30 days
  - [ ] Log aggregation working

---

## 🔄 Backup & Recovery

### Backup Configuration
- [ ] TimescaleDB backup schedule
  - [ ] Frequency: Daily
  - [ ] Retention: 30 days
  - [ ] Destination: S3 bucket `________________________`

- [ ] Grafana dashboard backups
  - [ ] Export dashboards to Git
  - [ ] Commit frequency: On change

- [ ] Configuration backups
  - [ ] Kubernetes manifests in Git
  - [ ] ConfigMaps backed up

### Recovery Testing
- [ ] Document recovery procedures
- [ ] Test restore from backup (quarterly)
- [ ] Measure RTO: `________________________` (target: 2 hours)
- [ ] Measure RPO: `________________________` (target: 1 hour)

---

## 📚 Documentation

### Internal Documentation
- [ ] Create runbooks for common tasks
  - [ ] Scaling executors
  - [ ] Restarting services
  - [ ] Troubleshooting failures

- [ ] Document custom configurations
- [ ] Create architecture diagrams (if customized)
- [ ] Maintain change log

### Knowledge Transfer
- [ ] Train DevOps team
  - [ ] Date: `________________________`
  - [ ] Attendees: `________________________`

- [ ] Train Analytics team
  - [ ] Date: `________________________`
  - [ ] Attendees: `________________________`

- [ ] Create user guides
  - [ ] Dashboard usage
  - [ ] Query writing
  - [ ] Report generation

---

## 🚦 Go-Live Checklist

### Pre-Production
- [ ] Performance testing completed
  - [ ] Load test: 100GB processed successfully
  - [ ] Stress test: Peak load handled
  - [ ] Endurance test: 24 hours stable

- [ ] Security review completed
  - [ ] Penetration testing done
  - [ ] Vulnerability scan passed
  - [ ] Compliance requirements met (GDPR, etc.)

- [ ] Disaster recovery tested
  - [ ] Backup verified
  - [ ] Restore tested
  - [ ] Failover tested

### Production Deployment
- [ ] Production cluster ready
  - [ ] Nodes: `______` (count)
  - [ ] CPU: `______` (total cores)
  - [ ] Memory: `______` (total GB)
  - [ ] Storage: `______` (total GB)

- [ ] Deploy to production
  ```bash
  ./scripts/deploy-all.sh
  ```

- [ ] Smoke tests passed
  - [ ] Sample data processed
  - [ ] Dashboards loading
  - [ ] Queries working
  - [ ] Alerts firing (test)

### Post-Deployment
- [ ] Monitor for 24 hours
  - [ ] No errors in logs
  - [ ] Resources within limits
  - [ ] Performance acceptable

- [ ] Notify stakeholders
  - [ ] Email sent: Yes / No
  - [ ] Documentation shared: Yes / No
  - [ ] Training scheduled: Yes / No

- [ ] Update documentation
  - [ ] Production URLs documented
  - [ ] Access procedures documented
  - [ ] Support contacts listed

---

## 📞 Support Contacts

### Internal Team
- **DevOps Lead**: `________________________`
- **Data Engineer**: `________________________`
- **Analytics Lead**: `________________________`

### Vendors
- **Akamai Support**: https://control.akamai.com/support
- **AWS Support**: https://console.aws.amazon.com/support
- **Kubernetes**: https://kubernetes.io/docs/

### On-Call Rotation
- **Week 1**: `________________________`
- **Week 2**: `________________________`
- **Week 3**: `________________________`
- **Week 4**: `________________________`

---

## ✅ Sign-Off

### Technical Review
- [ ] Reviewed by: `________________________`
- [ ] Date: `________________________`
- [ ] Comments: `________________________`

### Security Review
- [ ] Reviewed by: `________________________`
- [ ] Date: `________________________`
- [ ] Comments: `________________________`

### Business Approval
- [ ] Approved by: `________________________`
- [ ] Date: `________________________`
- [ ] Comments: `________________________`

---

## 📝 Post-Deployment Notes

### Issues Encountered
```
Date       | Issue                | Resolution                | Time to Resolve
-----------|----------------------|---------------------------|----------------
           |                      |                           |
           |                      |                           |
           |                      |                           |
```

### Lessons Learned
```
1. ___________________________________________________________________________

2. ___________________________________________________________________________

3. ___________________________________________________________________________
```

### Improvement Suggestions
```
1. ___________________________________________________________________________

2. ___________________________________________________________________________

3. ___________________________________________________________________________
```

---

## 🎉 Deployment Complete!

**Deployment Date**: `________________________`

**Deployed By**: `________________________`

**Production URL**: `________________________`

**Dashboard URL**: `________________________`

**Status**: 🟢 Operational

---

**Next Review Date**: `________________________`

**Review Cycle**: Monthly / Quarterly / Annually (circle one)

